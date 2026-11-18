# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only dependency fixtures used by the parent resolver.

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
    Dependabot::Bun::UpdateChecker::PackageLatestVersionFinder.new(
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
        Dependabot::DependencyFile.new(
          name: "bun.lock",
          content: {
            "lockfileVersion" => 1,
            "packages" => {
              "react" => ["react@15.2.0", "", {}],
              "react-dom" => ["react-dom@15.2.0", "", {}]
            }
          }.to_json
        )
      ]
    end
    let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "react-dom",
        version: "15.2.0",
        package_manager: "bun",
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

    before do
      allow(Dependabot::Bun::Helpers).to receive(:run_bun_command) do |command, **|
        command_string = command.is_a?(Array) ? command.join(" ") : command
        next "" unless command_string.include?("@16.3.1")

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
        allow(Dependabot::Bun::Helpers).to receive(:run_bun_command)
          .and_return("react-dom@16.3.1 requires a peer of react@^16 but none is installed.")
      end

      it "ignores successful stdout and caches the empty result" do
        2.times { expect(resolver.latest_resolvable_version).to eq(latest_allowable_version) }
        expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).once
      end
    end

    context "with an unrecognized helper failure" do
      before do
        allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "unrecognized failure", error_context: {})
        )
      end

      it "preserves the fallback to the latest version" do
        expect(resolved_version).to eq(latest_allowable_version)
      end
    end

    context "with an unrelated execution error" do
      before do
        allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_raise(TypeError, "unrelated error")
      end

      it "does not disguise the error as an empty conflict list" do
        expect { resolved_version }.to raise_error(TypeError, "unrelated error")
      end
    end

    context "with a pre-existing conflict for the same names and a different range" do
      let(:peers) { ["unconsumed"] }

      before do
        allow(Dependabot::Bun::Helpers).to receive(:run_bun_command) do |command, **|
          command_string = command.is_a?(Array) ? command.join(" ") : command
          range = command_string.include?("@16.3.1") ? "^16.0.0" : "^14.0.0"
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
          package_manager: "bun",
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

  %w(workspace_dependency_not_at_root workspace_dependency_not_at_root_v1
     workspace_dependency_not_at_root_v3).each do |project|
    describe "#latest_resolvable_version with a dependency only declared in a nested workspace (#{project})" do
      subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

      let(:project_name) { "bun/#{project}" }
      let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.0.1",
          requirements: [{
            file: "packages/app/package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: nil
          }],
          package_manager: "bun"
        )
      end

      it { is_expected.to eq(latest_allowable_version) }

      it "scopes the peer dependency check to the workspace that declares the dependency" do
        allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_call_original

        latest_resolvable_version

        # Without --filter, bun update at the repo root fails with "is not a
        # dependency of this workspace" for a workspace-only dependency.
        expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).with(
          ["update", "etag@1.8.1", "--filter", "./packages/app", "--save-text-lockfile", "--ignore-scripts"],
          fingerprint: "update <dependency_name>@<version> --save-text-lockfile --ignore-scripts"
        )
      end
    end
  end

  describe "#latest_resolvable_version with a dependency declared in a nested project with its own lockfile" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    let(:project_name) { "bun/nested_lockfile_workspace_dependency" }
    let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.1",
        requirements: [{
          file: "packages/member/package.json",
          requirement: "^1.0.0",
          groups: ["devDependencies"],
          source: nil
        }],
        package_manager: "bun"
      )
    end

    it { is_expected.to eq(latest_allowable_version) }

    it "checks the dependency from within the nested project, without a stale repo-root-relative filter" do
      allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_call_original

      latest_resolvable_version

      # DependencyFilesFilterer#paths_requiring_update_check returns
      # "packages/member" for this nested project, and run_bun_checker then
      # chdirs there. A filter built relative to the repository root (e.g.
      # "./packages/member") would therefore point Bun at the non-existent
      # "packages/member/packages/member".
      expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).with(
        ["update", "etag@1.8.1", "--save-text-lockfile", "--ignore-scripts"],
        fingerprint: "update <dependency_name>@<version> --save-text-lockfile --ignore-scripts"
      )
    end
  end

  describe "#latest_resolvable_version with the same dependency declared in two sibling nested projects" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    let(:project_name) { "bun/sibling_nested_lockfile_dependency" }
    let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.1",
        requirements: [
          {
            file: "packages/a/package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: nil
          },
          {
            file: "packages/b/package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: nil
          }
        ],
        package_manager: "bun"
      )
    end

    it { is_expected.to eq(latest_allowable_version) }

    it "doesn't leak one nested project's filter into the other's check" do
      allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_call_original

      latest_resolvable_version

      # Each nested project has its own lockfile and is checked separately,
      # chdir'd into its own path. Without restricting candidate manifests
      # to the current project's subtree, the sibling's requirement would
      # turn into a filter like "./packages/b" while chdir'd into
      # "packages/a", pointing Bun at the non-existent
      # "packages/a/packages/b".
      expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).with(
        ["update", "etag@1.8.1", "--save-text-lockfile", "--ignore-scripts"],
        fingerprint: "update <dependency_name>@<version> --save-text-lockfile --ignore-scripts"
      ).twice
    end
  end

  describe "#latest_resolvable_version with a dependency only consumed via a workspace catalog" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    let(:project_name) { "bun/catalog_workspace" }
    let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.1",
        requirements: [{
          requirement: "1.0.1",
          file: "package.json",
          groups: ["dependencies"],
          source: nil,
          metadata: { catalog: "testing" }
        }],
        package_manager: "bun"
      )
    end

    it { is_expected.to eq(latest_allowable_version) }

    it "scopes the check to the workspace that consumes the catalog entry" do
      allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_call_original

      latest_resolvable_version

      # Bun::FileParser records catalog dependencies against the root
      # package.json even when only a nested workspace consumes them via
      # "catalog:", so requirement.file alone can't identify the declaring
      # workspace here. The root package.json itself doesn't depend on
      # "etag", so an unfiltered root update would fail with "is not a
      # dependency of this workspace".
      expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).with(
        ["update", "etag@1.8.1", "--filter", "./packages/app", "--save-text-lockfile", "--ignore-scripts"],
        fingerprint: "update <dependency_name>@<version> --save-text-lockfile --ignore-scripts"
      )
    end
  end

  describe "#latest_resolvable_version with the same dependency declared in two workspaces" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    let(:project_name) { "bun/shared_workspace_dependency" }
    let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.1",
        requirements: [
          {
            file: "packages/a/package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: nil
          },
          {
            file: "packages/b/package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: nil
          }
        ],
        package_manager: "bun"
      )
    end

    it { is_expected.to eq(latest_allowable_version) }

    it "checks peer dependencies separately for each declaring workspace" do
      allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_call_original

      latest_resolvable_version

      # Bun merges same-name declarations into one Dependency, so without a
      # check per declaring workspace, peer conflicts in the other workspace
      # would never be evaluated.
      expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).with(
        ["update", "etag@1.8.1", "--filter", "./packages/a", "--save-text-lockfile", "--ignore-scripts"],
        fingerprint: "update <dependency_name>@<version> --save-text-lockfile --ignore-scripts"
      )
      expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).with(
        ["update", "etag@1.8.1", "--filter", "./packages/b", "--save-text-lockfile", "--ignore-scripts"],
        fingerprint: "update <dependency_name>@<version> --save-text-lockfile --ignore-scripts"
      )
    end
  end

  describe "#latest_resolvable_version with a dependency declared only in an unnamed workspace" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    let(:project_name) { "bun/unnamed_workspace_dependency" }
    let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.1",
        requirements: [{
          file: "packages/app/package.json",
          requirement: "^1.0.0",
          groups: ["devDependencies"],
          source: nil
        }],
        package_manager: "bun"
      )
    end

    it "fails explicitly instead of silently falling back to an unfiltered root check" do
      # Unreachable in practice: Bun refuses to run any command against a
      # repo with an unnamed workspace. Kept as a defensive guard.
      expect { latest_resolvable_version }
        .to raise_error(Dependabot::DependencyFileNotParseable, /must declare a "name"/)
    end
  end

  describe "#latest_resolvable_version with a workspace package named using a glob metacharacter" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    let(:project_name) { "bun/glob_metacharacter_workspace_name" }
    let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.1",
        requirements: [{
          file: "packages/app-star/package.json",
          requirement: "^1.0.0",
          groups: ["devDependencies"],
          source: nil
        }],
        package_manager: "bun"
      )
    end

    it { is_expected.to eq(latest_allowable_version) }

    it "scopes the peer dependency check by path instead of the package's glob-like name" do
      allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_call_original

      latest_resolvable_version

      # Name is "app*". Passed directly to --filter, Bun would treat it as a
      # glob and match unrelated workspaces too.
      expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).with(
        ["update", "etag@1.8.1", "--filter", "./packages/app-star", "--save-text-lockfile", "--ignore-scripts"],
        fingerprint: "update <dependency_name>@<version> --save-text-lockfile --ignore-scripts"
      )
    end
  end

  describe "#latest_resolvable_version with a workspace directory path containing a space" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    let(:project_name) { "bun/workspace_path_with_space" }
    let(:latest_allowable_version) { Gem::Version.new("1.8.1") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.1",
        requirements: [{
          file: "packages/my app/package.json",
          requirement: "^1.0.0",
          groups: ["devDependencies"],
          source: nil
        }],
        package_manager: "bun"
      )
    end

    it { is_expected.to eq(latest_allowable_version) }

    it "passes the filter path as a single argument instead of splitting on the space" do
      allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_call_original

      latest_resolvable_version

      # A single interpolated string would be whitespace-split before
      # shelling out, breaking "packages/my app" into two arguments.
      expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).with(
        ["update", "etag@1.8.1", "--filter", "./packages/my app", "--save-text-lockfile", "--ignore-scripts"],
        fingerprint: "update <dependency_name>@<version> --save-text-lockfile --ignore-scripts"
      )
    end
  end
end
