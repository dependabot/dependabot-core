# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"

path_namespace = "dependabot/update_checkers/java_script/npm_and_yarn/"
require path_namespace + "latest_version_finder"

namespace = Dependabot::UpdateCheckers::JavaScript::NpmAndYarn
RSpec.describe namespace::LatestVersionFinder do
  let(:registry_listing_url) { "https://registry.npmjs.org/etag" }
  let(:registry_response) do
    fixture("javascript", "npm_responses", "etag.json")
  end
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
      ignored_versions: ignored_versions
    )
  end
  let(:ignored_versions) { [] }
  let(:dependency_files) { [package_json] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("javascript", "package_files", manifest_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "package.json" }

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
      version: "1.0.0",
      requirements: [
        { file: "package.json", requirement: "^1.0.0", groups: [], source: nil }
      ],
      package_manager: "npm_and_yarn"
    )
  end

  describe "#latest_version_details_from_registry" do
    subject { version_finder.latest_version_details_from_registry }
    its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }

    it "only hits the registry once" do
      version_finder.latest_version_details_from_registry
      expect(WebMock).to have_requested(:get, registry_listing_url).once
    end

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.7.0.a, < 1.8"] }
      before do
        stub_request(:get, registry_listing_url + "/1.6.0").
          to_return(status: 200)
      end
      its([:version]) { is_expected.to eq(Gem::Version.new("1.6.0")) }
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
      its([:version]) { is_expected.to eq(Gem::Version.new("1.5.1")) }
    end

    context "when the latest version is a prerelease" do
      before do
        body = fixture("javascript", "npm_responses", "prerelease.json")
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/2.0.0-rc1").
          to_return(status: 200)
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }

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

        its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }
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

        its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }
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

        # Note: this is the dist-tag latest version, *not* the latest prerelease
        its([:version]) { is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1")) }

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

          its([:version]) do
            is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1"))
          end

          context "specified with a dash" do
            let(:requirement) { "^2.0.0-pre" }
            its([:version]) do
              is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1"))
            end
          end
        end
      end
    end

    context "for a private npm-hosted dependency" do
      before do
        body = fixture("javascript", "npm_responses", "prerelease.json")
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
          to_return(status: 404, body: "{\"error\":\"Not found\"}")
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

        its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }
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
          expect { version_finder.latest_version_details_from_registry }.
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
          body = fixture("javascript", "npm_responses", "prerelease.json")
          stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 404, body: "{\"error\":\"Not found\"}")
          stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
            with(headers: { "Authorization" => "Basic c2VjcmV0OnRva2Vu" }).
            to_return(status: 200, body: body)
        end

        its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end
    end

    context "for a dependency hosted on another registry" do
      before do
        body = fixture("javascript", "gemfury_response_etag.json")
        stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
          to_return(status: 404, body: "{\"error\":\"Not found\"}")
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
              type: "private_registry",
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
          expect { version_finder.latest_version_details_from_registry }.
            to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
              expect(error.source).to eq("npm.fury.io/dependabot")
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

        its([:version]) { is_expected.to eq(Gem::Version.new("1.8.1")) }

        context "when the latest version has been yanked" do
          before do
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/1.8.1"
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

          its([:version]) { is_expected.to eq(Gem::Version.new("1.8.0")) }
        end

        context "when the registry doesn't implement the /version endpoint" do
          before do
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@blep%2Fblep/latest"
            ).to_return(status: 404)
          end

          its([:version]) { is_expected.to eq(Gem::Version.new("1.8.1")) }
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

          its([:version]) { is_expected.to eq(Gem::Version.new("1.8.1")) }
        end

        context "without https" do
          before do
            body = fixture("javascript", "gemfury_response_etag.json")
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
                  type: "private_registry",
                  url: "http://npm.fury.io/dependabot"
                }
              }],
              package_manager: "npm_and_yarn"
            )
          end

          its([:version]) { is_expected.to eq(Gem::Version.new("1.8.1")) }
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
          expect { version_finder.latest_version_details_from_registry }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("npm.fury.io/dependabot")
            end
        end

        context "with credentials in the .npmrc" do
          let(:dependency_files) { [npmrc] }
          let(:npmrc) do
            Dependabot::DependencyFile.new(
              name: ".npmrc",
              content: fixture("javascript", "npmrc", "auth_token")
            )
          end

          its([:version]) { is_expected.to eq(Gem::Version.new("1.8.1")) }

          context "that require an environment variable" do
            let(:npmrc) do
              Dependabot::DependencyFile.new(
                name: ".npmrc",
                content: fixture("javascript", "npmrc", "env_auth_token")
              )
            end

            it "raises a PrivateSourceAuthenticationFailure error" do
              error_class = Dependabot::PrivateSourceAuthenticationFailure
              expect { version_finder.latest_version_details_from_registry }.
                to raise_error(error_class) do |error|
                  expect(error.source).to eq("npm.fury.io/dependabot")
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
            body: fixture("javascript", "npm_responses", "etag.json")
          )
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }
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
        body = fixture("javascript", "npm_responses", "prerelease.json")
        stub_request(:get, registry_listing_url).
          to_raise(Excon::Error::Timeout).then.
          to_return(status: 200, body: body)
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "when the latest version has been yanked" do
      before do
        body = fixture("javascript", "npm_responses", "old_latest.json")
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/1.7.0").
          to_return(status: 404)
        stub_request(:get, registry_listing_url + "/1.6.0").
          to_return(status: 200)
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.6.0")) }
    end

    context "when the npm link resolves to a 403" do
      before do
        stub_request(:get, registry_listing_url).
          to_return(status: 403, body: "{\"error\":\"Forbidden\"}")

        # Speed up spec by stopping any sleep logic
        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_details_from_registry }.
          to raise_error(described_class::RegistryError)
      end
    end

    context "when the npm link resolves to a 404" do
      before do
        stub_request(:get, registry_listing_url).
          to_return(status: 404, body: "{\"error\":\"Not found\"}")

        # Speed up spec by stopping any sleep logic
        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_details_from_registry }.
          to raise_error(described_class::RegistryError)
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
          expect { version_finder.latest_version_details_from_registry }.
            to_not raise_error
        end
      end

      context "for a namespaced dependency" do
        before do
          stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
            to_return(status: 404, body: "{\"error\":\"Not found\"}")
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
          expect { version_finder.latest_version_details_from_registry }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("registry.npmjs.org")
            end
        end
      end
    end

    context "when the latest version is older than another, non-prerelease" do
      before do
        body = fixture("javascript", "npm_responses", "old_latest.json")
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/1.6.0").
          to_return(status: 200)
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.6.0")) }

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

        its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }
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

        its([:version]) { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { version_finder.latest_resolvable_version_with_no_unlock }

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
  end

  describe "#possible_versions" do
    subject(:possible_versions) { version_finder.possible_versions }

    it "returns a list of versions" do
      expect(possible_versions).to eq(
        [
          Dependabot::Utils::JavaScript::Version.new("1.7.0"),
          Dependabot::Utils::JavaScript::Version.new("1.6.0"),
          Dependabot::Utils::JavaScript::Version.new("1.5.1"),
          Dependabot::Utils::JavaScript::Version.new("1.5.0"),
          Dependabot::Utils::JavaScript::Version.new("1.4.0"),
          Dependabot::Utils::JavaScript::Version.new("1.3.1"),
          Dependabot::Utils::JavaScript::Version.new("1.3.0"),
          Dependabot::Utils::JavaScript::Version.new("1.2.1"),
          Dependabot::Utils::JavaScript::Version.new("1.2.0"),
          Dependabot::Utils::JavaScript::Version.new("1.1.0"),
          Dependabot::Utils::JavaScript::Version.new("1.0.1"),
          Dependabot::Utils::JavaScript::Version.new("1.0.0")
        ]
      )
    end

    context "when some versions are being ignored" do
      let(:ignored_versions) { [">= 1.1.0, < 1.6"] }

      it "excludes the ignored versions" do
        expect(possible_versions).to eq(
          [
            Dependabot::Utils::JavaScript::Version.new("1.7.0"),
            Dependabot::Utils::JavaScript::Version.new("1.6.0"),
            Dependabot::Utils::JavaScript::Version.new("1.0.1"),
            Dependabot::Utils::JavaScript::Version.new("1.0.0")
          ]
        )
      end
    end
  end

  describe "#possible_versions_with_details" do
    subject(:possible_versions_with_details) do
      version_finder.possible_versions_with_details
    end

    context "with versions that would be considered equivalent" do
      let(:registry_response) do
        fixture("javascript", "npm_responses", "react-test-renderer.json")
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
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
        expect { possible_versions_with_details }.to_not raise_error
      end
    end
  end
end
