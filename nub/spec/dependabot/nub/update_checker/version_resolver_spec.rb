# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nub/update_checker/version_resolver"

RSpec.describe Dependabot::Nub::UpdateChecker::VersionResolver do
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
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
  let(:group) { nil }
  let(:latest_version_finder) do
    Dependabot::Nub::UpdateChecker::PackageLatestVersionFinder.new(
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
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#latest_resolvable_version peer metadata boundary" do
    subject(:resolved_version) { resolver.latest_resolvable_version }

    let(:project_name) { "javascript/peer_dependency_no_lockfile" }
    let(:dependency_files) do
      [
        *super(),
        # nub.lock is a pnpm v9 lockfile, not bun's JSON one. Both packages must parse as locked at
        # 15.2.0, or the full-unlock path reads react-dom's current version from the registry instead.
        Dependabot::DependencyFile.new(
          name: "nub.lock",
          content: <<~YAML
            lockfileVersion: '9.0'

            settings:
              autoInstallPeers: true
              excludeLinksFromLockfile: false

            importers:

              .:
                dependencies:
                  react:
                    specifier: ^15.2.0
                    version: 15.2.0
                  react-dom:
                    specifier: ^15.2.0
                    version: 15.2.0(react@15.2.0)

            packages:

              react-dom@15.2.0:
                resolution: {integrity: sha1-zJuaL1HkYNanJ8eyMFj+lPQsh0w=}
                peerDependencies:
                  react: ^15.2.0

              react@15.2.0:
                resolution: {integrity: sha1-y4VEmxDHS6jNS94M0oZ7Xu4JqXQ=}

            snapshots:

              react-dom@15.2.0(react@15.2.0):
                dependencies:
                  react: 15.2.0

              react@15.2.0: {}
          YAML
        )
      ]
    end
    let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "react-dom",
        version: "15.2.0",
        package_manager: "nub",
        requirements: [{ file: "package.json", requirement: "^15.2.0", groups: ["dependencies"], source: nil }]
      )
    end
    let(:peers) { { "react" => "^16.0.0" } }
    let(:current_peers) { { "react" => "^15.0.0" } }
    let(:react_dom_registry_response) do
      {
        "versions" => {
          "15.2.0" => { "peerDependencies" => current_peers },
          "16.3.1" => { "peerDependencies" => peers },
          "17.0.0" => { "deprecated" => "unused", "peerDependencies" => ["unconsumed"] }
        },
        "dist-tags" => { "latest" => "16.3.1" }
      }.to_json
    end

    # Bun names the candidate on the command line (`update <name>@<version>`). Nub pins it into
    # package.json and re-resolves with `install --lockfile-only`, so these stubs read it back from
    # the manifest that run_nub_checker has just written.
    def candidate_pinned?
      JSON.parse(File.read("package.json")).fetch("dependencies").value?("16.3.1")
    end

    before do
      allow(Dependabot::Nub::Helpers).to receive(:run_nub_command) do
        next "" unless candidate_pinned?

        raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "react-dom@16.3.1 requires a peer of react@^16.0.0 but none is installed.",
          error_context: {}
        )
      end
    end

    it "rejects an unsatisfied candidate without reading deprecated release metadata" do
      expect(resolved_version).to eq(Gem::Version.new("15.2.0"))
    end

    [nil, false, {}].each do |value|
      context "with peer requirements set to #{value.inspect}" do
        let(:peers) { value }

        it "retains the no-peer-requirements behavior" do
          expect(resolved_version).to eq(latest_allowable_version)
        end
      end
    end

    context "with malformed peer metadata on the current version" do
      let(:current_peers) { ["unconsumed"] }

      it "retains the current-version shortcut" do
        expect(resolved_version).to eq(Gem::Version.new("15.2.0"))
      end
    end

    context "with a malformed candidate peer map" do
      let(:peers) { ["invalid"] }

      it "raises a contextual type error instead of a helper fallback" do
        expect { resolved_version }.to raise_error(TypeError, /react-dom.*16\.3\.1.*peerDependencies/)
      end
    end

    context "with a malformed later peer requirement" do
      let(:peers) { { "react" => "<0", "other" => 1 } }

      it "decodes the complete map before checking compatibility" do
        expect { resolved_version }.to raise_error(TypeError, /peerDependencies values must be strings/)
      end
    end

    context "with invalid requirement syntax" do
      let(:peers) { { "react" => "not a requirement" } }

      it "rejects the candidate through the existing syntax handling" do
        expect(resolved_version).to eq(Gem::Version.new("15.2.0"))
      end
    end

    context "when the checker succeeds" do
      before do
        allow(Dependabot::Nub::Helpers).to receive(:run_nub_command)
          .and_return("react-dom@16.3.1 requires a peer of react@^16 but none is installed.")
      end

      it "ignores successful stdout and caches the empty result" do
        2.times { expect(resolver.latest_resolvable_version).to eq(latest_allowable_version) }
        expect(Dependabot::Nub::Helpers).to have_received(:run_nub_command).once
      end
    end

    context "with an unrecognized helper failure" do
      before do
        allow(Dependabot::Nub::Helpers).to receive(:run_nub_command).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "unrecognized failure", error_context: {})
        )
      end

      it "preserves the fallback to the latest version" do
        expect(resolved_version).to eq(latest_allowable_version)
      end
    end

    context "with an unrelated execution error" do
      before do
        allow(Dependabot::Nub::Helpers).to receive(:run_nub_command).and_raise(TypeError, "unrelated error")
      end

      it "does not disguise the error as an empty conflict list" do
        expect { resolved_version }.to raise_error(TypeError, "unrelated error")
      end
    end

    context "with a pre-existing conflict for the same names and a different range" do
      let(:peers) { ["unconsumed"] }

      before do
        allow(Dependabot::Nub::Helpers).to receive(:run_nub_command) do
          range = candidate_pinned? ? "^16.0.0" : "^14.0.0"
          raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "react-dom@16.3.1 requires a peer of react@#{range} but none is installed.",
            error_context: {}
          )
        end
      end

      it "removes the pre-existing conflict by name pair" do
        expect(resolved_version).to eq(latest_allowable_version)
      end
    end

    context "when the updated dependency is required by a peer" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "react",
          version: "15.2.0",
          package_manager: "nub",
          requirements: [{ file: "package.json", requirement: "^15.2.0", groups: ["dependencies"], source: nil }]
        )
      end
      let(:current_peers) { ["unconsumed"] }

      it "preserves full-unlock payloads and skips non-newer peer candidates before decoding" do
        updates = resolver.dependency_updates_from_full_unlock

        expect(updates.first[:dependency]).to be(dependency)
        expect(updates.map(&:keys)).to eq([%i(dependency version previous_version)] * 2)
        expect(updates.map { |update| [update[:dependency].name, update[:version].to_s, update[:previous_version]] })
          .to eq([["react", "16.3.1", "15.2.0"], ["react-dom", "16.3.1", "15.2.0"]])
      end
    end
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
            package_manager: "nub"
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
            package_manager: "nub"
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
              package_manager: "nub"
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
              package_manager: "nub",
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
              package_manager: "nub",
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
                package_manager: "nub",
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
          package_manager: "nub",
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
            package_manager: "nub",
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
            package_manager: "nub",
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
            package_manager: "nub",
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
            package_manager: "nub",
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
            package_manager: "nub",
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
            package_manager: "nub",
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
            package_manager: "nub",
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
            package_manager: "nub",
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
            package_manager: "nub",
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
