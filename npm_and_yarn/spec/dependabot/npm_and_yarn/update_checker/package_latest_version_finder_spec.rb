# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker/latest_version_finder"
require "dependabot/credential"
require "dependabot/security_advisory"
require "dependabot/package/release_cooldown_options"
require "dependabot/npm_and_yarn/version"
require "dependabot/npm_and_yarn/package/package_details_fetcher"

RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::PackageLatestVersionFinder do
  let(:registry_base) { "https://registry.npmjs.org" }
  let(:version_finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      raise_on_ignored: raise_on_ignored,
      cooldown_options: cooldown_options
    )
  end

  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:dependency_name) { "etag" }
  let(:escaped_dependency_name) { dependency_name.gsub("/", "%2F") }
  let(:unscoped_dependency_name) { dependency_name.split("/").last }
  let(:target_version) { "1.7.0" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [
        { file: "package.json", requirement: "^1.0.0", groups: [], source: nil }
      ],
      package_manager: "npm_and_yarn"
    )
  end
  let(:dependency_version) { "1.0.0" }
  let(:registry_listing_url) { "#{registry_base}/#{escaped_dependency_name}" }
  let(:registry_response) { fixture("npm_responses", "#{escaped_dependency_name}.json") }
  let(:login_form) { fixture("npm_responses", "login_form.html") }
  let(:cooldown_options) { nil }

  before do
    stub_request(:get, registry_listing_url)
      .to_return(status: 200, body: registry_response)
    stub_request(:head, "#{registry_base}/#{dependency_name}/-/#{unscoped_dependency_name}-#{target_version}.tgz")
      .to_return(status: 200)
  end

  describe "#latest_version_from_registry" do
    subject(:latest_version_from_registry) { version_finder.latest_version_from_registry }

    it { is_expected.to eq(Gem::Version.new("1.7.0")) }

    it "only hits the registry once" do
      version_finder.latest_version_from_registry
      expect(WebMock).to have_requested(:get, registry_listing_url).once
    end

    context "when raise_on_ignored is enabled and later versions are allowed" do
      let(:raise_on_ignored) { true }

      it "doesn't raise an error" do
        expect { latest_version_from_registry }.not_to raise_error
      end
    end

    context "when the user is on the latest version" do
      let(:dependency_version) { "1.7.0" }

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "doesn't raise an error" do
          expect { latest_version_from_registry }.not_to raise_error
        end
      end
    end

    context "when the user is ignoring all later versions" do
      let(:ignored_versions) { ["> 1.0.0"] }
      let(:target_version) { "1.0.0" }

      it { is_expected.to eq(Gem::Version.new("1.0.0")) }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "raises an error" do
          expect { latest_version_from_registry }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.7.0.a, < 1.8"] }
      let(:target_version) { "1.6.0" }

      it { is_expected.to eq(Gem::Version.new("1.6.0")) }
    end

    context "when the current version isn't known" do
      let(:dependency_version) { nil }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "doesn't raise an error" do
          expect { latest_version_from_registry }.not_to raise_error
        end
      end
    end

    context "when the dependency is a git dependency" do
      let(:dependency_version) { "a1b78a929dac93a52f08db4f2847d76d6cfe39bd" }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "doesn't raise an error" do
          expect { latest_version_from_registry }.not_to raise_error
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
      let(:target_version) { "1.5.1" }

      it { is_expected.to eq(Gem::Version.new("1.5.1")) }
    end

    context "when the latest version is a prerelease" do
      before do
        body = fixture("npm_responses", "prerelease.json")
        stub_request(:get, registry_listing_url)
          .to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/2.0.0-rc1")
          .to_return(status: 200)
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

      context "when the user wants a .x version" do
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

      context "when the user is on an old pre-release" do
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

      context "when the user is on a pre-release for this version" do
        let(:target_version) { "2.0.0-rc1" }
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

        context "when only says so in their requirements (with a .)" do
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

          context "when specified with a dash" do
            let(:requirement) { "^2.0.0-pre" }

            it { is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1")) }
          end
        end
      end
    end

    context "when dealing with a private npm-hosted dependency" do
      before do
        body = fixture("npm_responses", "prerelease.json")
        stub_request(:get, "https://registry.npmjs.org/@dependabot%2Fblep")
          .to_return(status: 404, body: '{"error":"Not found"}')
        stub_request(:get, "https://registry.npmjs.org/@dependabot%2Fblep")
          .with(headers: { "Authorization" => "Bearer secret_token" })
          .to_return(status: 200, body: body)
        stub_request(:head, "https://registry.npmjs.org/@dependabot/blep/-/blep-1.7.0.tgz")
          .to_return(status: 200)
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@dependabot/blep",
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
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }), Dependabot::Credential.new({
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "secret_token"
          })]
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end

      context "without credentials" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          })]
        end

        before do
          stub_request(:get, "https://www.npmjs.com/package/@dependabot/blep")
            .to_return(status: 200, body: login_form)
        end

        it "raises a Dependabot::PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { version_finder.latest_version_from_registry }
            .to raise_error(error_class) do |error|
              expect(error.source).to eq("registry.npmjs.org")
            end
        end
      end

      context "when the login page is rate limited" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          })]
        end

        before do
          stub_request(:get, "https://www.npmjs.com/package/@dependabot/blep")
            .to_return(status: 429, body: "")
        end

        it "raises a Dependabot::PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { version_finder.latest_version_from_registry }
            .to raise_error(error_class) do |error|
              expect(error.source).to eq("registry.npmjs.org")
            end
        end
      end

      context "with Basic auth credentials" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }), Dependabot::Credential.new({
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "secret:token"
          })]
        end

        before do
          body = fixture("npm_responses", "prerelease.json")
          stub_request(:get, "https://registry.npmjs.org/@dependabot%2Fblep")
            .with(headers: { "Authorization" => "Bearer secret_token" })
            .to_return(status: 404, body: '{"error":"Not found"}')
          stub_request(:get, "https://registry.npmjs.org/@dependabot%2Fblep")
            .with(headers: { "Authorization" => "Basic c2VjcmV0OnRva2Vu" })
            .to_return(status: 200, body: body)
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end
    end

    context "when dealing with a dependency hosted on another registry" do
      before do
        body = fixture("gemfury_responses", "gemfury_response_etag.json")
        stub_request(:get, "https://npm.fury.io/dependabot/@dependabot%2Fblep")
          .to_return(status: 404, body: '{"error":"Not found"}')
        stub_request(:get, "https://npm.fury.io/dependabot/@dependabot%2Fblep")
          .with(headers: { "Authorization" => "Bearer secret_token" })
          .to_return(status: 200, body: body)
        stub_request(:get, "https://npm.fury.io/dependabot/@dependabot%2Fblep/1.8.1")
          .to_return(status: 200)
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@dependabot/blep",
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
          stub_request(:get, "https://npm.fury.io/dependabot/@dependabot%2Fblep")
            .with(headers: { "Authorization" => "Bearer secret_token" })
            .to_timeout
          stub_request(:get, "https://npm.fury.io/dependabot/@dependabot%2Fblep")
            .to_timeout

          # Speed up spec by stopping any sleep logic
          allow(version_finder).to receive(:sleep).and_return(true)
        end

        it "raises a to Dependabot::PrivateSourceTimedOut error" do
          expect { version_finder.latest_version_from_registry }
            .to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
              expect(error.source).to eq("npm.fury.io/<redacted>")
            end
        end

        context "when dealing with a git dependency" do
          before do
            allow_any_instance_of(Dependabot::NpmAndYarn::Package::PackageDetailsFetcher) # rubocop:disable RSpec/AnyInstance
              .to receive(:dependency_url)
              .and_return("https://npm.fury.io/dependabot/@dependabot%2Fblep")
          end

          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@dependabot/blep",
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
          stub_request(:get, "https://npm.fury.io/dependabot/@dependabot%2Fblep")
            .with(headers: { "Authorization" => "Bearer secret_token" })
            .to_return(status: 500)
          stub_request(:get, "https://npm.fury.io/dependabot/@dependabot%2Fblep")
            .to_return(status: 500)

          # Speed up spec by stopping any sleep logic
          allow(version_finder).to receive(:sleep).and_return(true)
        end

        it "raises an error" do
          expect { version_finder.latest_version_from_registry }
            .to raise_error do |err|
              expect(err.class).to eq(Dependabot::DependencyFileNotResolvable)
            end
        end
      end

      context "when the request 200s with a bad body" do
        before do
          stub_request(:get, "https://npm.fury.io/dependabot/@dependabot%2Fblep")
            .with(headers: { "Authorization" => "Bearer secret_token" })
            .to_return(
              status: 200,
              body: 'user "undefined" is not a member of "KaterTech"'
            )
        end

        it "raises a to Dependabot::PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { version_finder.latest_version_from_registry }
            .to raise_error(error_class) do |error|
              expect(error.source).to eq("npm.fury.io/<redacted>")
            end
        end
      end

      context "with credentials" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }), Dependabot::Credential.new({
            "type" => "npm_registry",
            "registry" => "npm.fury.io/dependabot",
            "token" => "secret_token"
          })]
        end

        it { is_expected.to eq(Gem::Version.new("1.8.1")) }

        context "when the latest version has been yanked" do
          before do
            allow_any_instance_of(Dependabot::NpmAndYarn::Package::PackageDetailsFetcher) # rubocop:disable RSpec/AnyInstance
              .to receive(:dependency_url)
              .and_return("https://npm.fury.io/dependabot/@dependabot%2Fblep")
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot%2Fblep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot/blep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot%2Fblep/latest"
            ).to_return(status: 200)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot%2Fblep/1.8.0"
            ).to_return(status: 200)
          end

          it { is_expected.to eq(Dependabot::NpmAndYarn::Version.new("1.8.0")) }
        end

        context "when the registry doesn't implement the /version endpoint" do
          before do
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot%2Fblep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot/blep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot%2Fblep/latest"
            ).to_return(status: 404)
          end

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }
        end

        context "when the registry doesn't escape dependency URLs properly" do
          # Looking at you JFrog...
          before do
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot%2Fblep/1.8.1"
            ).to_return(status: 404)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot/blep/1.8.1"
            ).to_return(status: 200)
            stub_request(
              :get,
              "https://npm.fury.io/dependabot/@dependabot%2Fblep/latest"
            ).to_return(status: 200)
          end

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }
        end

        context "without a lockfile" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@dependabot/blep",
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
            stub_request(:get, "https://npm.fury.io/dependabot/@dependabot%2Fblep")
              .with(headers: { "Authorization" => "Bearer secret_token" })
              .to_return(status: 404)
            stub_request(:get, "http://npm.fury.io/dependabot/@dependabot%2Fblep")
              .with(headers: { "Authorization" => "Bearer secret_token" })
              .to_return(status: 200, body: body)
            stub_request(
              :get, "http://npm.fury.io/dependabot/@dependabot%2Fblep/1.8.1"
            ).to_return(status: 200)
          end

          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@dependabot/blep",
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
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          })]
        end

        it "raises a to Dependabot::PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { version_finder.latest_version_from_registry }
            .to raise_error(error_class) do |error|
              expect(error.source).to eq("npm.fury.io/<redacted>")
            end
        end

        context "with credentials in the .npmrc" do
          let(:dependency_files) { project_dependency_files(project_name).select { |f| f.name == ".npmrc" } }
          let(:project_name) { "npm6/npmrc_auth_token" }

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }

          context "when it require an environment variable" do
            let(:project_name) { "npm6/npmrc_env_auth_token" }

            it "raises a PrivateSourceAuthenticationFailure error" do
              error_class = Dependabot::PrivateSourceAuthenticationFailure
              expect { version_finder.latest_version_from_registry }
                .to raise_error(error_class) do |error|
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
        stub_request(:get, registry_listing_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(
            status: 200,
            body: fixture("npm_responses", "etag.json")
          )
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "when the npm link resolves to an empty hash" do
      before do
        stub_request(:get, registry_listing_url)
          .to_return(status: 200, body: "{}")
      end

      it { is_expected.to be_nil }
    end

    context "when the npm link fails at first" do
      before do
        body = fixture("npm_responses", "prerelease.json")
        stub_request(:get, registry_listing_url)
          .to_raise(Excon::Error::Timeout).then
          .to_return(status: 200, body: body)
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "when the latest version has been yanked" do
      before do
        body = fixture("npm_responses", "old_latest.json")
        stub_request(:get, registry_listing_url)
          .to_return(status: 200, body: body)
        stub_request(:head, "#{registry_base}/etag/-/etag-1.7.0.tgz")
          .to_return(status: 404)
        stub_request(:head, "#{registry_base}/etag/-/etag-1.6.0.tgz")
          .to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.6.0")) }
    end

    context "when the npm link resolves to a 403" do
      before do
        stub_request(:get, registry_listing_url)
          .to_return(status: 403, body: '{"error":"Forbidden"}')

        # Speed up spec by stopping any sleep logic
        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_from_registry }
          .to raise_error(Dependabot::RegistryError)
      end
    end

    context "when the npm link returns 200 but invalid JSON object in body" do
      before do
        body = fixture("npm_responses", "200_with_invalid_json.json")
        stub_request(:get, registry_listing_url)
          .to_return(status: 200, body: body)

        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_from_registry }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when the npm link returns 200 but valid JSON object in body" do
      before do
        body = fixture("npm_responses", "200_with_valid_json.json")
        stub_request(:get, registry_listing_url)
          .to_return(status: 200, body: body)

        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_from_registry }
          .not_to raise_error
      end
    end

    context "when the npm link resolves to a 404" do
      before do
        stub_request(:get, registry_listing_url)
          .to_return(status: 404, body: '{"error":"Not found"}')

        # Speed up spec by stopping any sleep logic
        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_from_registry }
          .to raise_error do |err|
            expect(err.class).to eq(Dependabot::RegistryError)
            expect(err.status).to eq(404)
          end
      end

      context "when dealing with a library dependency" do
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
          expect { version_finder.latest_version_from_registry }
            .not_to raise_error
        end
      end

      context "when dealing with a namespaced dependency" do
        before do
          stub_request(:get, "https://registry.npmjs.org/@dependabot%2Fblep")
            .to_return(status: 404, body: '{"error":"Not found"}')
          stub_request(:get, "https://www.npmjs.com/package/@dependabot/blep")
            .to_return(status: 200, body: login_form)
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "@dependabot/blep",
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
          expect { version_finder.latest_version_from_registry }
            .to raise_error(error_class) do |error|
              expect(error.source).to eq("registry.npmjs.org")
            end
        end

        context "when it can be found on www.npmjs.com" do
          before do
            stub_request(:get, "https://www.npmjs.com/package/@dependabot/blep")
              .to_return(
                status: 200,
                body: fixture("npm_responses", "babel-core.html")
              )
          end

          it "raises an error" do
            expect { version_finder.latest_version_from_registry }
              .to raise_error(Dependabot::RegistryError)
          end
        end
      end
    end

    context "when the latest version is older than another, non-prerelease" do
      before do
        body = fixture("npm_responses", "old_latest.json")
        stub_request(:get, registry_listing_url)
          .to_return(status: 200, body: body)
        stub_request(:head, "#{registry_base}/etag/-/etag-1.6.0.tgz")
          .to_return(status: 200)
        stub_request(:head, "#{registry_base}/etag/-/etag-1.6.3.tgz")
          .to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.6.0")) }

      context "when the user is already using" do
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

      context "when the user has pinned in their package.json" do
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

    context "when the npm registry package lookup returns a 404 error" do
      before do
        stub_request(:get, registry_listing_url)
          .to_return(status: 404, body: '{"error":"Not found"}')

        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_from_registry }
          .to raise_error do |err|
            expect(err.class).to eq(Dependabot::RegistryError)
            expect(err.status).to eq(404)
          end
      end
    end

    context "when the dependency has been yanked" do
      before do
        stub_request(:head, "#{registry_base}/etag/-/etag-1.6.0.tgz")
          .to_return(status: 200)
        stub_request(:head, "#{registry_base}/etag/-/etag-1.6.3.tgz")
          .to_return(status: 200)
      end

      let(:registry_response) do
        fixture("npm_responses", "etag_yanked.json")
      end

      it "picks the latest non-yanked dist-tags version" do
        expect(latest_version_from_registry).to eq(Gem::Version.new("1.6.3"))
      end
    end

    context "when the npm registry package lookup returns a 500 error" do
      before do
        stub_request(:get, registry_listing_url)
          .to_return(status: 500, body: '{"error":"Not found"}')

        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_from_registry }
          .to raise_error do |err|
            expect(err.class).to eq(Dependabot::DependencyFileNotResolvable)
          end
      end
    end

    context "when the npm registry uri is invalid and lookup returns a bad URI error" do
      before do
        stub_request(:get, registry_listing_url)
          .to_return(status: 500, body: '{"error":"bad URI(is not URI?): "https://registry.npmjs.org/\"/webpack""}')

        allow(version_finder).to receive(:sleep).and_return(true)
      end

      it "raises an error" do
        expect { version_finder.latest_version_from_registry }
          .to raise_error do |err|
            expect(err.class).to eq(Dependabot::DependencyFileNotResolvable)
          end
      end
    end
  end
end
