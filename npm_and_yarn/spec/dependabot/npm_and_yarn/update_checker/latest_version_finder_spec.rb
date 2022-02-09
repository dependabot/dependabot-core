# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker/latest_version_finder"

RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::LatestVersionFinder do
  let(:registry_listing_url) { "https://registry.npmjs.org/etag" }
  let(:registry_response) { fixture("npm_responses", "etag.json") }
  let(:login_form) { fixture("npm_responses", "login_form.html") }
  before do
    stub_request(:get, registry_listing_url).
      to_return(status: 200, body: registry_response)
    stub_request(:get, registry_listing_url + "/latest").
      to_return(status: 200, body: "{}")
    stub_request(:get, registry_listing_url + "/1.7.0").
      to_return(status: 200)
  end

  let(:version_finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories
    )
  end
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "etag",
      version: dependency_version,
      requirements: [
        { file: "package.json", requirement: "^1.0.0", groups: [], source: nil }
      ],
      package_manager: "npm_and_yarn"
    )
  end
  let(:dependency_version) { "1.0.0" }

  describe "#latest_version_from_registry" do
    subject { version_finder.latest_version_from_registry }
    it { is_expected.to eq(Gem::Version.new("1.7.0")) }

    it "only hits the registry once" do
      version_finder.latest_version_from_registry
      expect(WebMock).to have_requested(:get, registry_listing_url).once
    end

    context "raise_on_ignored when later versions are allowed" do
      let(:raise_on_ignored) { true }
      it "doesn't raise an error" do
        expect { subject }.to_not raise_error
      end
    end

    context "when the user is on the latest version" do
      let(:dependency_version) { "1.7.0" }
      it { is_expected.to eq(Gem::Version.new("1.7.0")) }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end
    end

    context "when the user is ignoring all later versions" do
      let(:ignored_versions) { ["> 1.0.0"] }
      before do
        stub_request(:get, registry_listing_url + "/1.0.0").
          to_return(status: 200)
      end
      it { is_expected.to eq(Gem::Version.new("1.0.0")) }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "raises an error" do
          expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.7.0.a, < 1.8"] }
      before do
        stub_request(:get, registry_listing_url + "/1.6.0").
          to_return(status: 200)
      end
      it { is_expected.to eq(Gem::Version.new("1.6.0")) }
    end

    context "when the current version isn't known" do
      let(:dependency_version) { nil }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end
    end

    context "when the dependency is a git dependency" do
      let(:dependency_version) { "a1b78a929dac93a52f08db4f2847d76d6cfe39bd" }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end
    end

    context "when the user wants a dist tag" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.0.0",
          requirements: [{
            file: "package.json",
            requirement: "stable",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end
      before do
        stub_request(:get, registry_listing_url + "/1.5.1").
          to_return(status: 200)
      end
      it { is_expected.to eq(Gem::Version.new("1.5.1")) }
    end

    context "when the latest version is a prerelease" do
      before do
        body = fixture("npm_responses", "prerelease.json")
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/2.0.0-rc1").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }

      context "when the user has specified a bad requirement" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.0.0",
            requirements: [{
              file: "package.json",
              requirement: "babel-core@^7.0.0-bridge.0",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to be_nil }
      end

      context "and the user wants a .x version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.7.0",
            requirements: [{
              file: "package.json",
              requirement: "1.x",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end

      context "and the user is on an old pre-release" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.7.0.beta1",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end

      context "and the user is on a pre-release for this version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "2.0.0.alpha",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        # NOTE: this is the dist-tag latest version, *not* the latest prerelease
        it { is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1")) }

        context "but only says so in their requirements (with a .)" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "etag",
              version: nil,
              requirements: [{
                file: "package.json",
                requirement: requirement,
                groups: [],
                source: nil
              }],
              package_manager: "npm_and_yarn"
            )
          end
          let(:requirement) { "^2.0.0-pre" }

          it { is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1")) }

          context "specified with a dash" do
            let(:requirement) { "^2.0.0-pre" }
            it { is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1")) }
          end
        end
      end
    end

    context "for a private npm-hosted dependency" do
      before do
        body = fixture("npm_responses", "prerelease.json")
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
          to_return(status: 404, body: '{"error":"Not found"}')
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
          with(headers: { "Authorization" => "Bearer secret_token" }).
          to_return(status: 200, body: body)
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep/1.7.0").
          to_return(status: 200)
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@blep/blep",
          version: "1.0.0",
          requirements: [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      context "with credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "secret_token"
          }]
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end

      context "without credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        end

        before do
          stub_request(:get, "https://www.npmjs.com/package/@blep/blep").
            to_return(status: 200, body: login_form)
        end

        it "raises a Dependabot::PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { version_finder.latest_version_from_registry }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("registry.npmjs.org")
            end
        end
      end

      context "when the login page is rate limited" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        end

        before do
          stub_request(:get, "https://www.npmjs.com/package/@blep/blep").
            to_return(status: 429, body: "")
        end

        it "raises a Dependabot::PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { version_finder.latest_version_from_registry }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("registry.npmjs.org")
            end
        end
      end

      context "with Basic auth credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "secret:token"
          }]
        end
        before do
          body = fixture("npm_responses", "prerelease.json")
          stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 404, body: '{"error":"Not found"}')
          stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
            with(headers: { "Authorization" => "Basic c2VjcmV0OnRva2Vu" }).
            to_return(status: 200, body: body)
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end
    end

    context "for a dependency hosted on another registry" do
      before do
        body = fixture("gemfury_responses", "gemfury_response_etag.json")
        stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
          to_return(status: 404, body: '{"error":"Not found"}')
        stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
          with(headers: { "Authorization" => "Bearer secret_token" }).
          to_return(status: 200, body: body)
        stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep/1.8.1").
          to_return(status: 200)
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@blep/blep",
          version: "1.0.0",
          requirements: [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: [],
            source: {
              type: "registry",
              url: "https://npm.fury.io/dependabot"
            }
          }],
          package_manager: "npm_and_yarn"
        )
      end

      context "when the request times out" do
        before do
          stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_timeout
          stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
            to_timeout

          # Speed up spec by stopping any sleep logic
          allow(version_finder).to receive(:sleep).and_return(true)
        end

        it "raises a to Dependabot::PrivateSourceTimedOut error" do
          expect { version_finder.latest_version_from_registry }.
            to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
              expect(error.source).to eq("npm.fury.io/<redacted>")
            end
        end

        context "for a git dependency" do
          before do
            allow(version_finder).
              to receive(:dependency_url).
              and_return("https://npm.fury.io/dependabot/@blep%2Fblep")
          end

          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@blep/blep",
              version: "1.0.0",
              requirements: [{
                file: "package.json",
                requirement: "^1.0.0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/unused/repo",
                  branch: nil,
                  ref: nil
                }
              }],
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to be_nil }
        end
      end

      context "when the request 500s" do
        before do
          stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 500)
          stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
            to_return(status: 500)

          # Speed up spec by stopping any sleep logic
          allow(version_finder).to receive(:sleep).and_return(true)
        end

        it { is_expected.to be_nil }
      end

      context "when the request 200s with a bad body" do
        before do
          stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(
              status: 200,
              body: 'user "undefined" is not a member of "KaterTech"'
            )
        end

        it "raises a to Dependabot::PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { version_finder.latest_version_from_registry }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("npm.fury.io/<redacted>")
            end
        end
      end

      context "with credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "npm_registry",
            "registry" => "npm.fury.io/dependabot",
            "token" => "secret_token"
          }]
        end

        it { is_expected.to eq(Gem::Version.new("1.8.1")) }

        context "when the latest version has been yanked" do
          before do
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep/blep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/latest"
            ).to_return(status: 200)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/1.8.0"
            ).to_return(status: 200)
          end

          it { is_expected.to eq(Gem::Version.new("1.8.0")) }
        end

        context "when the registry doesn't implement the /version endpoint" do
          before do
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep/blep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/latest"
            ).to_return(status: 404)
          end

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }
        end

        context "when the registry doesn't escape dependency URLs properly" do
          # Looking at you JFrog...
          before do
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep/blep/1.8.1"
            ).to_return(status: 200)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/latest"
            ).to_return(status: 200)
          end

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }
        end

        context "without a lockfile" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@blep/blep",
              version: nil,
              requirements: [{
                file: "package.json",
                requirement: "^1.0.0",
                groups: [],
                source: nil
              }],
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }
        end

        context "without https" do
          before do
            body = fixture("gemfury_responses", "gemfury_response_etag.json")
            stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 404)
            stub_request(:get, "http://npm.fury.io/dependabot/@blep%2Fblep").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 200, body: body)
            stub_request(
              :get, "http://npm.fury.io/dependabot/@blep%2Fblep/1.8.1"
            ).to_return(status: 200)
          end

          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@blep/blep",
              version: "1.0.0",
              requirements: [{
                file: "package.json",
                requirement: "^1.0.0",
                groups: [],
                source: {
                  type: "registry",
                  url: "http://npm.fury.io/dependabot"
                }
              }],
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }
        end
      end

      context "without credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        end

        it "raises a to Dependabot::PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { version_finder.latest_version_from_registry }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("npm.fury.io/<redacted>")
            end
        end

        context "with credentials in the .npmrc" do
          let(:dependency_files) { project_dependency_files(project_name).select { |f| f.name == ".npmrc" } }
          let(:project_name) { "npm6/npmrc_auth_token" }

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }

          context "that require an environment variable" do
            let(:project_name) { "npm6/npmrc_env_auth_token" }

            it "raises a PrivateSourceAuthenticationFailure error" do
              error_class = Dependabot::PrivateSourceAuthenticationFailure
              expect { version_finder.latest_version_from_registry }.
                to raise_error(error_class) do |error|
                  expect(error.source).to eq("npm.fury.io/<redacted>")
                end
            end
          end
        end
      end
    end

    context "when the npm link resolves to a redirect" do
      let(:redirect_url) { "https://registry.npmjs.org/eTag" }

      before do
        stub_request(:get, registry_listing_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(
            status: 200,
            body: fixture("npm_responses", "etag.json")
          )
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "when the npm link resolves to an empty hash" do
      before do
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: "{}")
      end

      it { is_expected.to be_nil }
    end

    context "when the npm link fails at first" do
      before do
        body = fixture("npm_responses", "prerelease.json")
        stub_request(:get, registry_listing_url).
          to_raise(Excon::Error::Timeout).then.
          to_return(status: 200, body: body)
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "when the latest version has been yanked" do
      before do
        body = fixture("npm_responses", "old_latest.json")
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/1.7.0").
          to_return(status: 404)
        stub_request(:get, registry_listing_url + "/1.6.0").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.6.0")) }
    end

    context "when the npm link resolves to a 403" do
      before do
        stub_request(:get, registry_listing_url).
          to_return(status: 403, body: '{"error":"Forbidden"}')

        # Speed up spec by stopping any sleep logic
        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_from_registry }.
          to raise_error(described_class::RegistryError)
      end
    end

    context "when the npm link resolves to a 404" do
      before do
        stub_request(:get, registry_listing_url).
          to_return(status: 404, body: '{"error":"Not found"}')

        # Speed up spec by stopping any sleep logic
        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_from_registry }.
          to raise_error do |err|
            expect(err.class).to eq(described_class::RegistryError)
            expect(err.status).to eq(404)
          end
      end

      context "for a library dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it "does not raise an error" do
          expect { version_finder.latest_version_from_registry }.
            to_not raise_error
        end
      end

      context "for a namespaced dependency" do
        before do
          stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
            to_return(status: 404, body: '{"error":"Not found"}')
          stub_request(:get, "https://www.npmjs.com/package/@blep/blep").
            to_return(status: 200, body: login_form)
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "@blep/blep",
            version: "1.0.0",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it "raises a to Dependabot::PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { version_finder.latest_version_from_registry }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("registry.npmjs.org")
            end
        end

        context "that can be found on www.npmjs.com" do
          before do
            stub_request(:get, "https://www.npmjs.com/package/@blep/blep").
              to_return(
                status: 200,
                body: fixture("npm_responses", "babel-core.html")
              )
          end

          it "raises an error" do
            expect { version_finder.latest_version_from_registry }.
              to raise_error(described_class::RegistryError)
          end
        end
      end
    end

    context "when the latest version is older than another, non-prerelease" do
      before do
        body = fixture("npm_responses", "old_latest.json")
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/1.6.0").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.6.0")) }

      context "that the user is already using" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.7.0",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end

      context "that the user has pinned in their package.json" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            requirements: [{
              file: "package.json",
              requirement: "^1.7.0",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end
    end

    context "when the dependency has been deprecated" do
      let(:registry_response) do
        fixture("npm_responses", "etag_deprecated.json")
      end

      it "picks the latest dist-tags version" do
        expect(subject).to eq(Gem::Version.new("1.7.0"))
      end
    end
  end

  describe "#latest_version_with_no_unlock" do
    subject { version_finder.latest_version_with_no_unlock }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.0",
        requirements: requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:requirements) do
      [{
        file: "package.json",
        requirement: req_string,
        groups: [],
        source: nil
      }]
    end
    let(:req_string) { "^1.0.0" }

    it { is_expected.to eq(Gem::Version.new("1.7.0")) }

    context "when a dist tag is specified" do
      let(:req_string) { "stable" }
      before do
        stub_request(:get, registry_listing_url + "/1.5.1").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.5.1")) }

      context "that can't be found" do
        let(:req_string) { "unknown" }

        # If the dist tag can't be found then we use the `latest` dist tag
        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end
    end

    context "when a version with a v-prefix is specified" do
      let(:req_string) { "v1.0.0" }
      before do
        stub_request(:get, registry_listing_url + "/1.0.0").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.0.0")) }
    end

    context "when constrained" do
      let(:req_string) { "<= 1.5.0" }
      before do
        stub_request(:get, registry_listing_url + "/1.5.0").
          to_return(status: 200)
      end
      it { is_expected.to eq(Gem::Version.new("1.5.0")) }

      context "by multiple requirements" do
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "<= 1.5.0",
            groups: [],
            source: nil
          }, {
            file: "package2.json",
            requirement: "^1.5.0",
            groups: [],
            source: nil
          }]
        end
        it { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end
    end

    context "when the dependency has been deprecated" do
      let(:registry_response) do
        fixture("npm_responses", "etag_deprecated.json")
      end

      it { is_expected.to eq(nil) }
    end
  end

  describe "#lowest_security_fix_version" do
    subject { version_finder.lowest_security_fix_version }
    before do
      stub_request(:get, registry_listing_url + "/1.2.1").
        to_return(status: 200)
    end

    let(:dependency_version) { "1.1.0" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: "rails",
          package_manager: "npm_and_yarn",
          vulnerable_versions: ["~1.1.0", "1.2.0", "1.3.0"]
        )
      ]
    end

    it { is_expected.to eq(Gem::Version.new("1.2.1")) }

    context "when the lowest version has been yanked" do
      before do
        stub_request(:get, registry_listing_url + "/1.2.1").
          to_return(status: 404)
        stub_request(:get, registry_listing_url + "/1.3.1").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.3.1")) }
    end

    context "when the user wants a dist tag" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.0.0",
          requirements: [{
            file: "package.json",
            requirement: "stable",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end
      before do
        stub_request(:get, registry_listing_url + "/1.5.1").
          to_return(status: 200)
      end
      it { is_expected.to eq(Gem::Version.new("1.5.1")) }
    end

    context "when the user has ignored all versions" do
      let(:ignored_versions) { [">= 0, < 99"] }

      it { is_expected.to be_nil }

      context "with raise_on_ignored" do
        let(:raise_on_ignored) { true }

        it "raises exception" do
          expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when the user has ignored all but vulnerable versions" do
      # 1.1.0 is not ignored, but it is vulnerable
      let(:ignored_versions) { ["> 0, < 1.1.0", "> 1.2.0, < 99"] }

      it { is_expected.to be_nil }

      context "with raise_on_ignored" do
        let(:raise_on_ignored) { true }

        it "raises exception" do
          expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end
  end

  describe "#possible_versions" do
    subject(:possible_versions) { version_finder.possible_versions }

    it "returns a list of versions" do
      expect(possible_versions).to eq(
        [
          Dependabot::NpmAndYarn::Version.new("1.7.0"),
          Dependabot::NpmAndYarn::Version.new("1.6.0"),
          Dependabot::NpmAndYarn::Version.new("1.5.1"),
          Dependabot::NpmAndYarn::Version.new("1.5.0"),
          Dependabot::NpmAndYarn::Version.new("1.4.0"),
          Dependabot::NpmAndYarn::Version.new("1.3.1"),
          Dependabot::NpmAndYarn::Version.new("1.3.0"),
          Dependabot::NpmAndYarn::Version.new("1.2.1"),
          Dependabot::NpmAndYarn::Version.new("1.2.0"),
          Dependabot::NpmAndYarn::Version.new("1.1.0"),
          Dependabot::NpmAndYarn::Version.new("1.0.1"),
          Dependabot::NpmAndYarn::Version.new("1.0.0")
        ]
      )
    end

    context "when some versions are being ignored" do
      let(:ignored_versions) { [">= 1.1.0, < 1.6"] }

      it "excludes the ignored versions" do
        expect(possible_versions).to eq(
          [
            Dependabot::NpmAndYarn::Version.new("1.7.0"),
            Dependabot::NpmAndYarn::Version.new("1.6.0"),
            Dependabot::NpmAndYarn::Version.new("1.0.1"),
            Dependabot::NpmAndYarn::Version.new("1.0.0")
          ]
        )
      end
    end

    context "when the dependency has been deprecated" do
      let(:registry_response) do
        fixture("npm_responses", "etag_deprecated.json")
      end

      it { is_expected.to eq([]) }
    end
  end

  describe "#possible_versions_with_details" do
    subject(:possible_versions_with_details) do
      version_finder.possible_versions_with_details
    end

    context "with versions that would be considered equivalent" do
      let(:registry_listing_url) do
        "https://registry.npmjs.org/react-test-renderer"
      end
      let(:registry_response) do
        fixture("npm_responses", "react-test-renderer.json")
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "react-test-renderer",
          version: "16.0.0-beta.5",
          requirements: [{
            file: "package.json",
            requirement: "16.0.0-beta.5",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "returns a list of versions" do
        expect(possible_versions_with_details.count).to eq(49)
      end
    end

    context "with ignored versions" do
      let(:registry_listing_url) { "https://registry.npmjs.org/react" }
      let(:registry_response) do
        fixture("npm_responses", "react.json")
      end
      let(:ignored_versions) { ["<15.0.0", "^16.0.0"] }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "react",
          version: "15.3.0",
          requirements: [{
            file: "package.json",
            requirement: "^15.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "excludes ignored versions" do
        versions = possible_versions_with_details
        latest_version = versions.first.first
        expect(versions.count).to eq(20)
        expect(latest_version).
          to eq(Dependabot::NpmAndYarn::Version.new("15.6.2"))
      end
    end

    context "with only deprecated versions" do
      let(:registry_response) do
        fixture("npm_responses", "etag_deprecated.json")
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.1.0",
          requirements: [{
            file: "package.json",
            requirement: "1.1.0",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "returns no versions" do
        expect(possible_versions_with_details).to eq([])
      end
    end
  end

  describe "#possible_previous_versions_with_details" do
    subject(:possible_previous_versions_with_details) do
      version_finder.possible_previous_versions_with_details
    end

    context "with ignored versions and non pre-release version requirement" do
      let(:registry_listing_url) { "https://registry.npmjs.org/react" }
      let(:registry_response) do
        fixture("npm_responses", "react.json")
      end
      let(:ignored_versions) { ["<15.0.0", "^16.0.0"] }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "react",
          version: "15.6.2",
          requirements: [{
            file: "package.json",
            requirement: "^15.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "includes ignored versions and excludes pre-releases" do
        versions = possible_previous_versions_with_details
        latest_version = versions.first.first
        expect(versions.count).to eq(80)
        expect(latest_version).
          to eq(Dependabot::NpmAndYarn::Version.new("16.6.0"))
      end
    end

    context "with pre-release version requirement" do
      let(:registry_listing_url) { "https://registry.npmjs.org/react" }
      let(:registry_response) do
        fixture("npm_responses", "react.json")
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "react",
          version: "15.6.0-rc.1",
          requirements: [{
            file: "package.json",
            requirement: "^15.6.0-rc.1",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "includes pre-released versions" do
        versions = possible_previous_versions_with_details
        latest_version = versions.first.first
        expect(versions.count).to eq(103)
        expect(latest_version).
          to eq(Dependabot::NpmAndYarn::Version.new("16.6.0"))
      end
    end

    context "with only deprecated versions" do
      let(:registry_response) do
        fixture("npm_responses", "etag_deprecated.json")
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.1.0",
          requirements: [{
            file: "package.json",
            requirement: "1.1.0",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "returns all versions" do
        expect(possible_previous_versions_with_details.count).to eq(13)
      end
    end
  end
end
