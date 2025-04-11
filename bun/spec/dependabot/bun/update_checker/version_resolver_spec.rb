# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bun/update_checker/version_resolver"

RSpec.describe Dependabot::Bun::UpdateChecker::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      latest_allowable_version: latest_allowable_version,
      latest_version_finder: latest_version_finder,
      repo_contents_path: repo_contents_path,
      dependency_group: group
    )
  end
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
  let(:dependency_files) { project_dependency_files(project_name) }
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
  let(:group) { nil }
  let(:latest_version_finder) do
    Dependabot::Bun::UpdateChecker::LatestVersionFinder.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: [],
      security_advisories: []
    )
  end
  let(:react_dom_registry_listing_url) do
    "https://registry.npmjs.org/react-dom"
  end
  let(:react_dom_registry_response) do
    fixture("npm_responses", "react-dom.json")
  end
  let(:react_registry_listing_url) { "https://registry.npmjs.org/react" }
  let(:react_registry_response) do
    fixture("npm_responses", "react.json")
  end
  let(:opentelemetry_api_registry_listing_url) { "https://registry.npmjs.org/%40opentelemetry%2Fapi" }
  let(:opentelemetry_api_registry_response) do
    fixture("npm_responses", "opentelemetry-api.json")
  end
  let(:opentelemetry_context_async_hooks_registry_listing_url) do
    "https://registry.npmjs.org/%40opentelemetry%2Fcontext-async-hooks"
  end
  let(:opentelemetry_context_async_hooks_registry_response) do
    fixture("npm_responses", "opentelemetry-context-async-hooks.json")
  end

  # Variable to control the enabling feature flag for the cooldown
  let(:enable_cooldown_for_bun) { true }

  before do
    stub_request(:get, react_dom_registry_listing_url)
      .to_return(status: 200, body: react_dom_registry_response)
    stub_request(:get, react_dom_registry_listing_url + "/latest")
      .to_return(status: 200, body: "{}")
    stub_request(:get, react_registry_listing_url)
      .to_return(status: 200, body: react_registry_response)
    stub_request(:get, react_registry_listing_url + "/latest")
      .to_return(status: 200, body: "{}")
    stub_request(:get, opentelemetry_api_registry_listing_url)
      .to_return(status: 200, body: opentelemetry_api_registry_response)
    stub_request(:get, opentelemetry_context_async_hooks_registry_listing_url)
      .to_return(status: 200, body: opentelemetry_context_async_hooks_registry_response)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_cooldown_for_bun).and_return(enable_cooldown_for_bun)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    context "with no lockfile" do
      context "when updating a tightly coupled monorepo dependency" do
        let(:project_name) { "javascript/peer_dependency_no_lockfile" }
        let(:latest_allowable_version) { Gem::Version.new("2.5.21") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "vue",
            version: nil,
            requirements: [{
              file: "package.json",
              requirement: "2.5.20",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }],
            package_manager: "bun"
          )
        end

        context "with other parts of the monorepo present" do
          let(:project_name) { "javascript/monorepo_dep_multiple_no_lockfile" }

          it { is_expected.to be_nil }
        end

        context "without other parts of the monorepo" do
          let(:project_name) { "javascript/monorepo_dep_single_no_lockfile" }

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "when updating a dependency without peer dependency issues" do
        let(:project_name) { "javascript/peer_dependency_no_lockfile" }
        let(:latest_allowable_version) { Gem::Version.new("1.0.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }],
            package_manager: "bun"
          )
        end

        it { is_expected.to eq(latest_allowable_version) }

        context "when requirement is a git dependency" do
          let(:project_name) { "javascript/git_dependency_no_lockfile" }
          let(:latest_allowable_version) do
            "0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "is-number",
              version: nil,
              requirements: [{
                requirement: nil,
                file: "package.json",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/jonschlinkert/is-number",
                  branch: nil,
                  ref: "master"
                }
              }],
              package_manager: "bun"
            )
          end

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "when there are already peer requirement issues" do
        let(:project_name) { "javascript/peer_dependency_mismatch_no_lockfile" }

        context "when dealing with a dependency with issues" do
          let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react",
              version: nil,
              package_manager: "bun",
              requirements: [{
                file: "package.json",
                requirement: "^15.2.0",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.npmjs.org" }
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("16.3.1")) }
        end

        context "when updating an unrelated dependency" do
          let(:latest_allowable_version) { Gem::Version.new("0.2.1") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "fetch-factory",
              version: nil,
              package_manager: "bun",
              requirements: [{
                file: "package.json",
                requirement: "^0.0.1",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.npmjs.org" }
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("0.2.1")) }

          context "with a dependency version that can't be found" do
            let(:project_name) { "javascript/yanked_version_no_lockfile" }
            let(:latest_allowable_version) { Gem::Version.new("99.0.0") }
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "fetch-factory",
                version: nil,
                package_manager: "bun",
                requirements: [{
                  file: "package.json",
                  requirement: "^99.0.0",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              )
            end

            # We let the latest version through here, rather than raising.
            # Eventually error handling should be moved from the FileUpdater
            # to here
            it { is_expected.to eq(Gem::Version.new("99.0.0")) }
          end
        end
      end
    end
  end

  describe "#dependency_updates_from_full_unlock" do
    subject { resolver.dependency_updates_from_full_unlock }

    describe "#dependency_updates_from_full_unlock resolves previous version" do
      subject do
        resolver.dependency_updates_from_full_unlock.first[:previous_version]
      end

      let(:project_name) { "javascript/exact_version_requirements_no_lockfile" }

      let(:latest_allowable_version) { Gem::Version.new("1.1.1") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "chalk",
          version: nil,
          package_manager: "bun",
          requirements: [{
            file: "package.json",
            requirement: "0.3.0",
            groups: ["dependencies"],
            source: { type: "registry", url: "https://registry.npmjs.org" }
          }]
        )
      end

      let(:listing_url) do
        "https://registry.npmjs.org/chalk"
      end
      let(:response) do
        fixture("npm_responses", "chalk.json")
      end

      before do
        stub_request(:get, listing_url)
          .to_return(status: 200, body: response)
        stub_request(:get, listing_url + "/latest")
          .to_return(status: 200, body: "{}")
      end

      it { is_expected.to eq("0.3.0") }
    end

    describe "#latest_resolvable_previous_version" do
      subject(:lrv) do
        resolver.latest_resolvable_previous_version(latest_allowable_version)
      end

      let(:project_name) { "javascript/exact_version_requirements_no_lockfile" }

      describe "when version requirement is exact" do
        let(:latest_allowable_version) { Gem::Version.new("1.1.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "chalk",
            version: nil,
            package_manager: "bun",
            requirements: [{
              file: "package.json",
              requirement: "0.3.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:listing_url) do
          "https://registry.npmjs.org/chalk"
        end
        let(:response) do
          fixture("npm_responses", "chalk.json")
        end

        before do
          stub_request(:get, listing_url)
            .to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest")
            .to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("0.3.0") }
      end

      describe "when version requirement is missing a patch" do
        let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: nil,
            package_manager: "bun",
            requirements: [{
              file: "package.json",
              requirement: "15.3",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:listing_url) do
          "https://registry.npmjs.org/react"
        end
        let(:response) do
          fixture("npm_responses", "react.json")
        end

        before do
          stub_request(:get, listing_url)
            .to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest")
            .to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("15.3.2") }
      end

      describe "with multiple version requirements" do
        let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: nil,
            package_manager: "bun",
            requirements: [{
              file: "package.json",
              requirement: "^15.4.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }, {
              file: "other/package.json",
              requirement: "< 15.0.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:listing_url) do
          "https://registry.npmjs.org/react"
        end
        let(:response) do
          fixture("npm_responses", "react.json")
        end

        before do
          stub_request(:get, listing_url)
            .to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest")
            .to_return(status: 200, body: "{}")
        end

        it "picks the lowest requirements max version" do
          expect(lrv).to eq("0.14.9")
        end
      end

      describe "when version requirement has a caret" do
        let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            package_manager: "bun",
            requirements: [{
              file: "package.json",
              requirement: "^1.1.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:listing_url) do
          "https://registry.npmjs.org/etag"
        end
        let(:response) do
          fixture("npm_responses", "etag.json")
        end

        before do
          stub_request(:get, listing_url)
            .to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest")
            .to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("1.7.0") }
      end

      describe "when all versions are deprecated" do
        let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            package_manager: "bun",
            requirements: [{
              file: "package.json",
              requirement: "^1.1.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:listing_url) do
          "https://registry.npmjs.org/etag"
        end
        let(:response) do
          fixture("npm_responses", "etag_deprecated.json")
        end

        before do
          stub_request(:get, listing_url)
            .to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest")
            .to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("1.7.0") }
      end

      describe "when current version requirement is deprecated" do
        let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: nil,
            package_manager: "bun",
            requirements: [{
              file: "package.json",
              requirement: "^0.7.1",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:listing_url) do
          "https://registry.npmjs.org/react"
        end
        let(:response) do
          fixture("npm_responses", "react.json")
        end

        before do
          stub_request(:get, listing_url)
            .to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest")
            .to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("0.7.1") }
      end

      context "when the resolved previous version is the same as the updated" do
        let(:latest_allowable_version) { Gem::Version.new("0.3.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "chalk",
            version: nil,
            package_manager: "bun",
            requirements: [{
              file: "package.json",
              requirement: "0.3.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:listing_url) do
          "https://registry.npmjs.org/chalk"
        end
        let(:response) do
          fixture("npm_responses", "chalk.json")
        end

        before do
          stub_request(:get, listing_url)
            .to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest")
            .to_return(status: 200, body: "{}")
        end

        it { is_expected.to be_nil }

        context "when the updated version is a string" do
          let(:latest_allowable_version) { "0.3.0" }

          it { is_expected.to be_nil }
        end
      end

      context "when the dependency has a previous version" do
        let(:latest_allowable_version) { Gem::Version.new("1.1.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "chalk",
            version: "0.2.0",
            package_manager: "bun",
            requirements: [{
              file: "package.json",
              requirement: "^0.2.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq("0.2.0") }
      end

      context "when the previous version is a git sha" do
        let(:latest_allowable_version) { Gem::Version.new("1.1.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "chalk",
            version: "9ec4acec6abd23f9b23e33b1171e50d41953f00d",
            package_manager: "bun",
            requirements: [{
              file: "package.json",
              requirement: nil,
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq("9ec4acec6abd23f9b23e33b1171e50d41953f00d") }
      end
    end
  end
end
