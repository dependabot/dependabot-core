# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker/version_resolver"

RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      latest_allowable_version: latest_allowable_version,
      latest_version_finder: latest_version_finder,
      repo_contents_path: nil
    )
  end
  let(:latest_version_finder) do
    Dependabot::NpmAndYarn::UpdateChecker::LatestVersionFinder.new(
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
  before do
    stub_request(:get, react_dom_registry_listing_url).
      to_return(status: 200, body: react_dom_registry_response)
    stub_request(:get, react_dom_registry_listing_url + "/latest").
      to_return(status: 200, body: "{}")
    stub_request(:get, react_registry_listing_url).
      to_return(status: 200, body: react_registry_response)
    stub_request(:get, react_registry_listing_url + "/latest").
      to_return(status: 200, body: "{}")
    stub_request(:get, opentelemetry_api_registry_listing_url).
      to_return(status: 200, body: opentelemetry_api_registry_response)
    stub_request(:get, opentelemetry_context_async_hooks_registry_listing_url).
      to_return(status: 200, body: opentelemetry_context_async_hooks_registry_response)
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  describe "#latest_resolvable_version" do
    subject { resolver.latest_resolvable_version }

    context "with an npm 8 package-lock.json using the v3 lockfile format" do
      context "updating a dependency without peer dependency issues" do
        let(:dependency_files) { project_dependency_files("npm8/package-lock-v3") }
        let(:latest_allowable_version) { Gem::Version.new("1.3.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "left-pad",
            version: "1.0.1",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.1",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(latest_allowable_version) }
      end
    end

    context "with a npm 8 package-lock.json" do
      context "updating a dependency without peer dependency issues" do
        let(:dependency_files) { project_dependency_files("npm8/package-lock") }
        let(:latest_allowable_version) { Gem::Version.new("1.3.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "left-pad",
            version: "1.0.1",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.1",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(latest_allowable_version) }
      end

      describe "updating a dependency with a peer requirement" do
        let(:dependency_files) { project_dependency_files("npm8/peer_dependency") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }
      end

      describe "updating a dependency with a peer requirement and some badly written peer dependency requirements" do
        let(:dependency_files) { project_dependency_files("npm8/peer_dependency") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end
        let(:react_dom_registry_response) do
          fixture("npm_responses", "react-dom-bad-reqs.json")
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }
      end

      describe "updating a dependency with a peer requirement that has (old) peer requirements that aren't included" do
        let(:dependency_files) { project_dependency_files("npm8/peer_dependency_changed") }
        let(:latest_allowable_version) { Gem::Version.new("2.2.4") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-apollo",
            version: "2.1.8",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^2.1.8",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:react_apollo_registry_listing_url) do
          "https://registry.npmjs.org/react-apollo"
        end
        let(:react_apollo_registry_response) do
          fixture("npm_responses", "react-apollo.json")
        end
        before do
          stub_request(:get, react_apollo_registry_listing_url).
            to_return(status: 200, body: react_apollo_registry_response)
          stub_request(:get, react_apollo_registry_listing_url + "/latest").
            to_return(status: 200, body: "{}")
        end

        # Upgrading react-apollo is blocked by our apollo-client version.
        # This test also checks that the old peer requirement on redux, which
        # is no longer in the package.json, doesn't cause any problems *and*
        # tests that complicated react peer requirements are processed OK.
        it { is_expected.to eq(Gem::Version.new("2.1.9")) }
      end

      describe "updating a dependency with a peer requirement that previously had the peer dep as a normal dep" do
        let(:dependency_files) { project_dependency_files("npm8/peer_dependency_switch") }
        let(:latest_allowable_version) { Gem::Version.new("2.5.4") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-burger-menu",
            version: "1.8.4",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "~1.8.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:react_burger_menu_registry_listing_url) do
          "https://registry.npmjs.org/react-burger-menu"
        end
        let(:react_burger_menu_registry_response) do
          fixture("npm_responses", "react-burger-menu.json")
        end
        before do
          stub_request(:get, react_burger_menu_registry_listing_url).
            to_return(status: 200, body: react_burger_menu_registry_response)
          stub_request(
            :get,
            react_burger_menu_registry_listing_url + "/latest"
          ).to_return(status: 200, body: "{}")
        end

        # NOTE: npm 8 automatically installs the peer requirement react and react-dom :tada:
        it { is_expected.to eq(Gem::Version.new("2.5.4")) }
      end

      describe "updating a dependency that is a peer requirement" do
        let(:dependency_files) { project_dependency_files("npm8/peer_dependency") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }
      end

      describe "updating a dependency that is a peer requirement with two semver constraints" do
        let(:dependency_files) { project_dependency_files("npm8/peer_dependency_two_semver_constraints") }
        let(:latest_allowable_version) { Gem::Version.new("1.1.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "@opentelemetry/api",
            version: "1.0.4",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: ">=1.0.0 <1.1.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("1.0.4")) }
      end

      describe "updating a dependency that is a peer requirement of multiple dependencies" do
        let(:dependency_files) { project_dependency_files("npm8/peer_dependency_multiple") }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: "0.14.2",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "0.14.2",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("0.14.9")) }
      end
    end

    context "with a npm 6 package-lock.json" do
      context "updating a dependency without peer dependency issues" do
        let(:dependency_files) { project_dependency_files("npm6/simple") }
        let(:latest_allowable_version) { Gem::Version.new("1.0.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.0.0",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(latest_allowable_version) }

        context "that is a git dependency" do
          let(:manifest_fixture_name) { "git_dependency.json" }
          let(:npm_lock_fixture_name) { "git_dependency.json" }
          let(:latest_allowable_version) do
            "0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "is-number",
              version: "af885e2e890b9ef0875edd2b117305119ee5bdc5",
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
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "updating a dependency with a peer requirement" do
        let(:dependency_files) { project_dependency_files("npm6/peer_dependency") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }

        context "and some badly written peer dependency requirements" do
          let(:react_dom_registry_response) do
            fixture("npm_responses", "react-dom-bad-reqs.json")
          end

          it { is_expected.to eq(Gem::Version.new("15.2.0")) }
        end

        context "that has (old) peer requirements that aren't included" do
          let(:dependency_files) { project_dependency_files("npm6/peer_dependency_changed") }
          let(:latest_allowable_version) { Gem::Version.new("2.2.4") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react-apollo",
              version: "2.1.8",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "^2.1.8",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.npmjs.org" }
              }]
            )
          end

          let(:react_apollo_registry_listing_url) do
            "https://registry.npmjs.org/react-apollo"
          end
          let(:react_apollo_registry_response) do
            fixture("npm_responses", "react-apollo.json")
          end
          before do
            stub_request(:get, react_apollo_registry_listing_url).
              to_return(status: 200, body: react_apollo_registry_response)
            stub_request(:get, react_apollo_registry_listing_url + "/latest").
              to_return(status: 200, body: "{}")
          end

          # Upgrading react-apollo is blocked by our apollo-client version.
          # This test also checks that the old peer requirement on redux, which
          # is no longer in the package.json, doesn't cause any problems *and*
          # tests that complicated react peer requirements are processed OK.
          it { is_expected.to eq(Gem::Version.new("2.1.9")) }
        end

        context "that previously had the peer dependency as a normal dep" do
          let(:dependency_files) { project_dependency_files("npm6/peer_dependency_switch") }
          let(:latest_allowable_version) { Gem::Version.new("2.5.4") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react-burger-menu",
              version: "1.8.4",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "~1.8.0",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.npmjs.org" }
              }]
            )
          end

          let(:react_burger_menu_registry_listing_url) do
            "https://registry.npmjs.org/react-burger-menu"
          end
          let(:react_burger_menu_registry_response) do
            fixture("npm_responses", "react-burger-menu.json")
          end
          before do
            stub_request(:get, react_burger_menu_registry_listing_url).
              to_return(status: 200, body: react_burger_menu_registry_response)
            stub_request(
              :get,
              react_burger_menu_registry_listing_url + "/latest"
            ).to_return(status: 200, body: "{}")
          end

          it { is_expected.to eq(Gem::Version.new("1.9.0")) }
        end
      end

      context "updating a dependency that is a peer requirement" do
        let(:dependency_files) { project_dependency_files("npm6/peer_dependency") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }

        context "of multiple dependencies" do
          let(:dependency_files) { project_dependency_files("npm6/peer_dependency_multiple") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react",
              version: "0.14.2",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "0.14.2",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.npmjs.org" }
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("0.14.9")) }
        end
      end
    end

    context "with a npm-shrinkwrap.json" do
      # Shrinkwrap case is mainly covered by package-lock.json specs (since
      # resolution is identical). Single spec ensures things are working
      context "updating a dependency with a peer requirement" do
        let(:dependency_files) { project_dependency_files("npm6/peer_dependency_shrinkwrap") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }
      end
    end

    context "with no lockfile" do
      context "updating a tightly coupled monorepo dep" do
        let(:dependency_files) { project_dependency_files("npm6/peer_dependency_no_lockfile") }
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
            package_manager: "npm_and_yarn"
          )
        end

        context "with other parts of the monorepo present" do
          let(:dependency_files) { project_dependency_files("npm6/monorepo_dep_multiple_no_lockfile") }
          it { is_expected.to be_nil }
        end

        context "without other parts of the monorepo" do
          let(:dependency_files) { project_dependency_files("npm6/monorepo_dep_single_no_lockfile") }
          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "updating a dependency without peer dependency issues" do
        let(:dependency_files) { project_dependency_files("npm6/peer_dependency_no_lockfile") }
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
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(latest_allowable_version) }

        context "that is a git dependency" do
          let(:dependency_files) { project_dependency_files("npm6/git_dependency_no_lockfile") }
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
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "updating a dependency with a peer requirement" do
        let(:dependency_files) { project_dependency_files("npm6/peer_dependency_no_lockfile") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        # We don't handle updates without a lockfile properly yet
        it { is_expected.to eq(Gem::Version.new("15.2.0")) }

        context "to an acceptable version" do
          let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
          it { is_expected.to eq(Gem::Version.new("15.6.2")) }
        end

        context "that is a git dependency" do
          let(:dependency_files) { project_dependency_files("npm6/peer_dependency_git_no_lockfile") }
          let(:latest_allowable_version) do
            "1af607cc24ee57b338c18e1a67eae445da86b316"
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@trainline/react-skeletor",
              version: nil,
              requirements: [{
                requirement: nil,
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/trainline/react-skeletor",
                  branch: nil,
                  ref: "master"
                }
              }],
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "updating a dependency that is a peer requirement" do
        let(:dependency_files) { project_dependency_files("npm6/peer_dependency_no_lockfile") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("16.3.1")) }
      end

      context "when there are already peer requirement issues" do
        let(:dependency_files) { project_dependency_files("npm6/peer_dependency_mismatch_no_lockfile") }

        context "for a dependency with issues" do
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
                source: { type: "registry", url: "https://registry.npmjs.org" }
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("16.3.1")) }
        end

        context "updating an unrelated dependency" do
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
                source: { type: "registry", url: "https://registry.npmjs.org" }
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("0.2.1")) }

          context "with a dependency version that can't be found" do
            let(:dependency_files) { project_dependency_files("npm6/yanked_version_no_lockfile") }
            let(:latest_allowable_version) { Gem::Version.new("99.0.0") }
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "fetch-factory",
                version: nil,
                package_manager: "npm_and_yarn",
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

    context "with a yarn berry lockfile" do
      context "updating a dependency with a peer requirement" do
        let(:dependency_files) { project_dependency_files("yarn_berry/peer_dependency") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }
      end
    end

    context "with a yarn.lock" do
      context "updating a dependency without peer dependency issues" do
        let(:dependency_files) { project_dependency_files("yarn/simple") }
        let(:latest_allowable_version) { Gem::Version.new("1.0.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.0.0",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(latest_allowable_version) }

        context "that is a git dependency" do
          let(:dependency_files) { project_dependency_files("yarn/git_dependency") }
          let(:latest_allowable_version) do
            "0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "is-number",
              version: "af885e2e890b9ef0875edd2b117305119ee5bdc5",
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
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "updating a dependency with a peer requirement" do
        let(:dependency_files) { project_dependency_files("yarn/peer_dependency") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }

        context "that previously had the peer dependency as a normal dep" do
          let(:dependency_files) { project_dependency_files("yarn/peer_dependency_switch") }
          let(:latest_allowable_version) { Gem::Version.new("2.5.4") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react-burger-menu",
              version: "1.8.4",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "~1.8.0",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.npmjs.org" }
              }]
            )
          end

          let(:react_burger_menu_registry_listing_url) do
            "https://registry.npmjs.org/react-burger-menu"
          end
          let(:react_burger_menu_registry_response) do
            fixture("npm_responses", "react-burger-menu.json")
          end
          before do
            stub_request(:get, react_burger_menu_registry_listing_url).
              to_return(status: 200, body: react_burger_menu_registry_response)
            stub_request(
              :get,
              react_burger_menu_registry_listing_url + "/latest"
            ).to_return(status: 200, body: "{}")
          end

          it { is_expected.to eq(Gem::Version.new("1.9.0")) }
        end
      end

      context "updating a dependency that is a peer requirement" do
        let(:dependency_files) { project_dependency_files("yarn/peer_dependency") }
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
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }

        context "of multiple dependencies" do
          let(:dependency_files) { project_dependency_files("yarn/peer_dependency_multiple") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react",
              version: "0.14.2",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "0.14.2",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.npmjs.org" }
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("0.14.9")) }
        end
      end
    end
  end

  describe "#latest_version_resolvable_with_full_unlock?" do
    subject { resolver.latest_version_resolvable_with_full_unlock? }

    context "npm 6: updating a tightly coupled monorepo dep" do
      let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
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
          package_manager: "npm_and_yarn"
        )
      end

      let(:vue_template_compiler_registry_listing_url) do
        "https://registry.npmjs.org/vue-template-compiler"
      end
      let(:vue_template_compiler_registry_response) do
        fixture("npm_responses", "vue-template-compiler.json")
      end
      let(:vue_registry_listing_url) { "https://registry.npmjs.org/vue" }
      let(:vue_registry_response) do
        fixture("npm_responses", "vue.json")
      end
      before do
        stub_request(:get, vue_template_compiler_registry_listing_url).
          to_return(status: 200, body: vue_template_compiler_registry_response)
        stub_request(
          :get,
          vue_template_compiler_registry_listing_url + "/latest"
        ).to_return(status: 200, body: "{}")
        stub_request(:get, vue_registry_listing_url).
          to_return(status: 200, body: vue_registry_response)
        stub_request(:get, vue_registry_listing_url + "/latest").
          to_return(status: 200, body: "{}")
      end

      context "with other parts of the monorepo present" do
        let(:manifest_fixture_name) { "monorepo_dep_multiple.json" }
        it { is_expected.to eq(true) }
      end
    end

    context "npm 6: updating a dependency that is a peer requirement" do
      let(:dependency_files) { project_dependency_files("npm6/peer_dependency") }
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
            source: { type: "registry", url: "https://registry.npmjs.org" }
          }]
        )
      end

      it { is_expected.to eq(true) }

      context "of multiple dependencies" do
        let(:dependency_files) { project_dependency_files("npm6/peer_dependency_multiple") }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: "0.14.2",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "0.14.2",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:react_modal_registry_listing_url) do
          "https://registry.npmjs.org/react-modal"
        end
        let(:react_modal_registry_response) do
          fixture("npm_responses", "react-modal.json")
        end
        before do
          stub_request(:get, react_modal_registry_listing_url).
            to_return(status: 200, body: react_modal_registry_response)
          stub_request(:get, react_modal_registry_listing_url + "/latest").
            to_return(status: 200, body: "{}")
        end

        # Support for React 16 gets added to react-modal after a new peer
        # dependency on react-dom is added. Dependabot doesn't know how to
        # handle updating packages with multiple peer dependencies, so bails.
        it { is_expected.to eq(false) }
      end
    end

    context "npm 6: updating a dependency with a peer requirement" do
      let(:dependency_files) { project_dependency_files("npm6/peer_dependency") }
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
            source: { type: "registry", url: "https://registry.npmjs.org" }
          }]
        )
      end

      it { is_expected.to eq(false) }
    end

    context "npm 8: updating a tightly coupled monorepo dep" do
      let(:dependency_files) { project_dependency_files("npm8/monorepo_dep_multiple") }
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
          package_manager: "npm_and_yarn"
        )
      end

      let(:vue_template_compiler_registry_listing_url) do
        "https://registry.npmjs.org/vue-template-compiler"
      end
      let(:vue_template_compiler_registry_response) do
        fixture("npm_responses", "vue-template-compiler.json")
      end
      let(:vue_registry_listing_url) { "https://registry.npmjs.org/vue" }
      let(:vue_registry_response) do
        fixture("npm_responses", "vue.json")
      end
      before do
        stub_request(:get, vue_template_compiler_registry_listing_url).
          to_return(status: 200, body: vue_template_compiler_registry_response)
        stub_request(
          :get,
          vue_template_compiler_registry_listing_url + "/latest"
        ).to_return(status: 200, body: "{}")
        stub_request(:get, vue_registry_listing_url).
          to_return(status: 200, body: vue_registry_response)
        stub_request(:get, vue_registry_listing_url + "/latest").
          to_return(status: 200, body: "{}")
      end

      context "with other parts of the monorepo present" do
        it { is_expected.to eq(true) }
      end
    end

    context "npm 8: updating a dependency that is a peer requirement" do
      let(:dependency_files) { project_dependency_files("npm8/peer_dependency_multiple") }
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
            source: { type: "registry", url: "https://registry.npmjs.org" }
          }]
        )
      end

      it { is_expected.to eq(true) }

      context "of multiple dependencies" do
        let(:dependency_files) { project_dependency_files("npm8/peer_dependency_multiple") }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: "0.14.2",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "0.14.2",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }]
          )
        end

        let(:react_modal_registry_listing_url) do
          "https://registry.npmjs.org/react-modal"
        end
        let(:react_modal_registry_response) do
          fixture("npm_responses", "react-modal.json")
        end
        before do
          stub_request(:get, react_modal_registry_listing_url).
            to_return(status: 200, body: react_modal_registry_response)
          stub_request(:get, react_modal_registry_listing_url + "/latest").
            to_return(status: 200, body: "{}")
        end

        # Support for React 16 gets added to react-modal after a new peer
        # dependency on react-dom is added. Dependabot doesn't know how to
        # handle updating packages with multiple peer dependencies, so bails.
        it { is_expected.to eq(false) }
      end
    end

    context "npm 8: updating a dependency with a peer requirement" do
      let(:dependency_files) { project_dependency_files("npm8/peer_dependency") }
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
            source: { type: "registry", url: "https://registry.npmjs.org" }
          }]
        )
      end

      it { is_expected.to eq(false) }
    end
  end

  describe "#dependency_updates_from_full_unlock" do
    subject { resolver.dependency_updates_from_full_unlock }

    context "npm 6: updating a tightly coupled monorepo dep" do
      let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
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
          package_manager: "npm_and_yarn"
        )
      end

      let(:vue_template_compiler_registry_listing_url) do
        "https://registry.npmjs.org/vue-template-compiler"
      end
      let(:vue_template_compiler_registry_response) do
        fixture("npm_responses", "vue-template-compiler.json")
      end
      let(:vue_registry_listing_url) { "https://registry.npmjs.org/vue" }
      let(:vue_registry_response) do
        fixture("npm_responses", "vue.json")
      end
      before do
        stub_request(:get, vue_template_compiler_registry_listing_url).
          to_return(status: 200, body: vue_template_compiler_registry_response)
        stub_request(
          :get,
          vue_template_compiler_registry_listing_url + "/latest"
        ).to_return(status: 200, body: "{}")
        stub_request(:get, vue_registry_listing_url).
          to_return(status: 200, body: vue_registry_response)
        stub_request(:get, vue_registry_listing_url + "/latest").
          to_return(status: 200, body: "{}")
      end

      context "with other parts of the monorepo present" do
        let(:dependency_files) { project_dependency_files("npm6/monorepo_dep_multiple_no_lockfile") }

        it "gets the right list of dependencies to update" do
          expect(resolver.dependency_updates_from_full_unlock).
            to match_array(
              [{
                dependency: Dependabot::Dependency.new(
                  name: "vue",
                  version: nil,
                  package_manager: "npm_and_yarn",
                  requirements: [{
                    file: "package.json",
                    requirement: "2.5.20",
                    groups: ["dependencies"],
                    source: nil
                  }]
                ),
                version: Dependabot::NpmAndYarn::Version.new("2.5.21"),
                previous_version: "2.5.20"
              }, {
                dependency: Dependabot::Dependency.new(
                  name: "vue-template-compiler",
                  version: nil,
                  package_manager: "npm_and_yarn",
                  requirements: [{
                    file: "package.json",
                    requirement: "2.5.20",
                    groups: ["dependencies"],
                    source: nil
                  }]
                ),
                version: Dependabot::NpmAndYarn::Version.new("2.5.21"),
                previous_version: "2.5.20"
              }]
            )
        end
      end
    end

    context "npm 6: updating a dependency that is a peer requirement" do
      let(:dependency_files) { project_dependency_files("npm6/peer_dependency") }
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
            source: { type: "registry", url: "https://registry.npmjs.org" }
          }]
        )
      end

      it "gets the right list of dependencies to update" do
        expect(resolver.dependency_updates_from_full_unlock).
          to match_array(
            [{
              dependency: Dependabot::Dependency.new(
                name: "react",
                version: "15.2.0",
                package_manager: "npm_and_yarn",
                requirements: [{
                  file: "package.json",
                  requirement: "^15.2.0",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              ),
              version: Dependabot::NpmAndYarn::Version.new("16.3.1"),
              previous_version: "15.2.0"
            }, {
              dependency: Dependabot::Dependency.new(
                name: "react-dom",
                version: "15.2.0",
                package_manager: "npm_and_yarn",
                requirements: [{
                  file: "package.json",
                  requirement: "^15.2.0",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              ),
              version: Dependabot::NpmAndYarn::Version.new("16.6.0"),
              previous_version: "15.2.0"
            }]
          )
      end
    end

    context "npm 8: updating a dependency that is a peer requirement" do
      let(:dependency_files) { project_dependency_files("npm8/peer_dependency") }
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
            source: { type: "registry", url: "https://registry.npmjs.org" }
          }]
        )
      end

      it "gets the right list of dependencies to update" do
        expect(resolver.dependency_updates_from_full_unlock).
          to contain_exactly(
            {
              dependency: Dependabot::Dependency.new(
                name: "react",
                version: "15.2.0",
                package_manager: "npm_and_yarn",
                requirements: [{
                  file: "package.json",
                  requirement: "^15.2.0",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              ),
              version: Dependabot::NpmAndYarn::Version.new("16.3.1"),
              previous_version: "15.2.0"
            }, {
              dependency: Dependabot::Dependency.new(
                name: "react-dom",
                version: "15.2.0",
                package_manager: "npm_and_yarn",
                requirements: [{
                  file: "package.json",
                  requirement: "^15.2.0",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              ),
              version: Dependabot::NpmAndYarn::Version.new("16.6.0"),
              previous_version: "15.2.0"
            }
          )
      end
    end

    context "yarn: updating a nested dependency that is a peer requirement" do
      let(:dependency_files) { project_dependency_files("yarn/peer_dependency_nested") }
      let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "react",
          version: "15.6.2",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "packages/package1/package.json",
            requirement: "15.6.2",
            groups: ["dependencies"],
            source: { type: "registry", url: "https://registry.yarnpkg.com" }
          }]
        )
      end
      let(:react_dom_registry_listing_url) do
        "https://registry.yarnpkg.com/react-dom"
      end

      it "gets the right list of dependencies to update" do
        expect(resolver.dependency_updates_from_full_unlock).
          to match_array(
            [{
              dependency: Dependabot::Dependency.new(
                name: "react",
                version: "15.6.2",
                package_manager: "npm_and_yarn",
                requirements: [{
                  file: "packages/package1/package.json",
                  requirement: "15.6.2",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.yarnpkg.com" }
                }]
              ),
              version: Dependabot::NpmAndYarn::Version.new("16.3.1"),
              previous_version: "15.6.2"
            }, {
              dependency: Dependabot::Dependency.new(
                name: "react-dom",
                version: "15.6.2",
                package_manager: "npm_and_yarn",
                requirements: [{
                  file: "packages/package1/package.json",
                  requirement: "15.6.2",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.yarnpkg.com" }
                }]
              ),
              version: Dependabot::NpmAndYarn::Version.new("16.6.0"),
              previous_version: "15.6.2"
            }]
          )
      end
    end

    context "updating duplicate nested dependencies with peer requirements" do
      let(:dependency_files) { project_dependency_files("npm6/peer_dependency_duplicate_nested_no_lockfile") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "react",
          version: nil,
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "packages/package1/package.json",
            requirement: "15.6.2",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package2/package.json",
            requirement: "15.6.2",
            groups: ["dependencies"],
            source: nil
          }]
        )
      end
      let(:latest_allowable_version) { Gem::Version.new("16.3.1") }

      it "gets the right list of dependencies to update" do
        resolved_dependencies = resolver.dependency_updates_from_full_unlock
        react = resolved_dependencies.find { |d| d[:dependency].name == "react" }
        react_dom = resolved_dependencies.find { |d| d[:dependency].name == "react-dom" }
        expect(react[:dependency].requirements).to contain_exactly(
          {
            file: "packages/package1/package.json",
            requirement: "15.6.2",
            groups: ["dependencies"],
            source: nil
          },
          {
            file: "packages/package2/package.json",
            requirement: "15.6.2",
            groups: ["dependencies"],
            source: nil
          }
        )
        expect(react_dom[:dependency].requirements).to contain_exactly(
          {
            requirement: "15.6.2",
            file: "packages/package2/package.json",
            groups: ["dependencies"],
            source: nil
          },
          {
            requirement: "15.6.2",
            file: "packages/package1/package.json",
            groups: ["dependencies"],
            source: nil
          }
        )
      end
    end

    context "#dependency_updates_from_full_unlock resolves previous version" do
      let(:dependency_files) { project_dependency_files("npm6/exact_version_requirements_no_lockfile") }
      subject do
        resolver.dependency_updates_from_full_unlock.first[:previous_version]
      end

      let(:latest_allowable_version) { Gem::Version.new("1.1.1") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "chalk",
          version: nil,
          package_manager: "npm_and_yarn",
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
        stub_request(:get, listing_url).
          to_return(status: 200, body: response)
        stub_request(:get, listing_url + "/latest").
          to_return(status: 200, body: "{}")
      end

      it { is_expected.to eq("0.3.0") }
    end

    context "#latest_resolvable_previous_version" do
      let(:dependency_files) { project_dependency_files("npm6/exact_version_requirements_no_lockfile") }
      subject do
        resolver.latest_resolvable_previous_version(latest_allowable_version)
      end

      describe "when version requirement is exact" do
        let(:latest_allowable_version) { Gem::Version.new("1.1.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "chalk",
            version: nil,
            package_manager: "npm_and_yarn",
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
          stub_request(:get, listing_url).
            to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest").
            to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("0.3.0") }
      end

      describe "when version requirement is missing a patch" do
        let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: nil,
            package_manager: "npm_and_yarn",
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
          stub_request(:get, listing_url).
            to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest").
            to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("15.3.2") }
      end

      describe "with multiple version requirements" do
        let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: nil,
            package_manager: "npm_and_yarn",
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
          stub_request(:get, listing_url).
            to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest").
            to_return(status: 200, body: "{}")
        end

        it "picks the lowest requirements max version" do
          is_expected.to eq("0.14.9")
        end
      end

      describe "when version requirement has a caret" do
        let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            package_manager: "npm_and_yarn",
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
          stub_request(:get, listing_url).
            to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest").
            to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("1.7.0") }
      end

      describe "when all versions are deprecated" do
        let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            package_manager: "npm_and_yarn",
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
          stub_request(:get, listing_url).
            to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest").
            to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("1.7.0") }
      end

      describe "when current version requirement is deprecated" do
        let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: nil,
            package_manager: "npm_and_yarn",
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
          stub_request(:get, listing_url).
            to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest").
            to_return(status: 200, body: "{}")
        end

        it { is_expected.to eq("0.7.1") }
      end

      context "when the resolved previous version is the same as the updated" do
        let(:latest_allowable_version) { Gem::Version.new("0.3.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "chalk",
            version: nil,
            package_manager: "npm_and_yarn",
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
          stub_request(:get, listing_url).
            to_return(status: 200, body: response)
          stub_request(:get, listing_url + "/latest").
            to_return(status: 200, body: "{}")
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
            package_manager: "npm_and_yarn",
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
            package_manager: "npm_and_yarn",
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
