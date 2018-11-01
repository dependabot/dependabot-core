# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java_script/npm_and_yarn/version_resolver"

namespace = Dependabot::UpdateCheckers::JavaScript::NpmAndYarn
RSpec.describe namespace::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      latest_allowable_version: latest_allowable_version,
      latest_version_finder: latest_version_finder
    )
  end
  let(:latest_allowable_version) { Gem::Version.new("1.0.0") }
  let(:latest_version_finder) do
    namespace::LatestVersionFinder.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: []
    )
  end
  let(:react_dom_registry_listing_url) do
    "https://registry.npmjs.org/react-dom"
  end
  let(:react_dom_registry_response) do
    fixture("javascript", "npm_responses", "react-dom.json")
  end
  let(:react_registry_listing_url) { "https://registry.npmjs.org/react" }
  let(:react_registry_response) do
    fixture("javascript", "npm_responses", "react.json")
  end
  before do
    stub_request(:get, react_dom_registry_listing_url).
      to_return(status: 200, body: react_dom_registry_response)
    stub_request(:get, react_dom_registry_listing_url + "/latest").
      to_return(status: 200, body: "{}")
    stub_request(:get, react_dom_registry_listing_url + "/16.6.0").
      to_return(status: 200)
    stub_request(:get, react_registry_listing_url).
      to_return(status: 200, body: react_registry_response)
    stub_request(:get, react_registry_listing_url + "/latest").
      to_return(status: 200, body: "{}")
    stub_request(:get, react_registry_listing_url + "/16.6.0").
      to_return(status: 200)
  end

  let(:dependency_files) { [package_json] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("javascript", "package_files", manifest_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "package.json" }
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: fixture("javascript", "yarn_lockfiles", yarn_lock_fixture_name)
    )
  end
  let(:yarn_lock_fixture_name) { "yarn.lock" }
  let(:npm_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("javascript", "npm_lockfiles", npm_lock_fixture_name)
    )
  end
  let(:npm_lock_fixture_name) { "package-lock.json" }
  let(:shrinkwrap) do
    Dependabot::DependencyFile.new(
      name: "npm-shrinkwrap.json",
      content: fixture("javascript", "npm_lockfiles", shrinkwrap_fixture_name)
    )
  end
  let(:shrinkwrap_fixture_name) { "package-lock.json" }

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
      requirements: [{
        file: "package.json",
        requirement: "^1.0.0",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "npm_and_yarn"
    )
  end

  describe "#latest_resolvable_version" do
    subject { resolver.latest_resolvable_version }

    context "with a package-lock.json" do
      let(:dependency_files) { [package_json, npm_lock] }

      context "updating a dependency without peer dependency issues" do
        it { is_expected.to eq(latest_allowable_version) }
      end

      context "updating a dependency with a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:npm_lock_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }
      end

      context "updating a dependency that is a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:npm_lock_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }
      end
    end

    context "with a npm-shrinkwrap.json" do
      let(:dependency_files) { [package_json, shrinkwrap] }

      context "updating a dependency without peer dependency issues" do
        it { is_expected.to eq(latest_allowable_version) }
      end

      context "updating a dependency with a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:shrinkwrap_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }
      end

      context "updating a dependency that is a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:shrinkwrap_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }
      end
    end

    context "with no lockfile" do
      let(:dependency_files) { [package_json] }

      context "updating a dependency without peer dependency issues" do
        let(:manifest_fixture_name) { "package.json" }
        it { is_expected.to eq(latest_allowable_version) }
      end

      context "updating a dependency with a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-dom",
            version: nil,
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        # We don't handle updates without a lockfile properly yet
        pending { is_expected.to eq(Gem::Version.new("15.2.0")) }

        context "to an acceptable version" do
          let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
          it { is_expected.to eq(Gem::Version.new("15.6.2")) }
        end
      end

      context "updating a dependency that is a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: nil,
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }

        context "to an acceptable version" do
          let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
          it { is_expected.to eq(Gem::Version.new("15.6.2")) }
        end
      end

      context "when there are already peer requirement issues" do
        let(:manifest_fixture_name) { "peer_dependency_mismatch.json" }
        let(:latest_allowable_version) { Gem::Version.new("0.2.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "fetch-factory",
            version: nil,
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^0.0.1",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("0.2.1")) }
      end
    end

    context "with a yarn.lock" do
      let(:dependency_files) { [package_json, yarn_lock] }

      context "updating a dependency without peer dependency issues" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "yarn.lock" }

        it { is_expected.to eq(latest_allowable_version) }
      end

      context "updating a dependency with a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:yarn_lock_fixture_name) { "peer_dependency.lock" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }
      end

      context "updating a dependency that is a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:yarn_lock_fixture_name) { "peer_dependency.lock" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }
      end
    end
  end
end
