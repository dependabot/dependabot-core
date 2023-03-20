# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/npm_and_yarn/metadata_finder"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::NpmAndYarn::UpdateChecker do
  it_behaves_like "an update checker"

  let(:registry_listing_url) { "https://registry.npmjs.org/etag" }
  let(:registry_response) do
    fixture("npm_responses", "etag.json")
  end
  before do
    stub_request(:get, registry_listing_url).
      to_return(status: 200, body: registry_response)
    stub_request(:get, registry_listing_url + "/latest").
      to_return(status: 200, body: "{}")
    stub_request(:get, registry_listing_url + "/1.7.0").
      to_return(status: 200)
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      options: options
    )
  end
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
  let(:options) { {} }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:dependency_name) { "etag" }
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

  describe "#vulnerable?" do
    context "when the dependency has multiple versions" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "foo",
          version: "1.0.0",
          requirements: (foo_v1.requirements + foo_v2.requirements).uniq,
          package_manager: "npm_and_yarn",
          metadata: { all_versions: [foo_v1, foo_v2] }
        )
      end

      let(:foo_v1) do
        Dependabot::Dependency.new(
          name: "foo",
          version: "1.0.0",
          requirements: [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: nil,
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      let(:foo_v2) do
        Dependabot::Dependency.new(
          name: "foo",
          version: "2.0.0",
          requirements: [{
            file: "package-lock.json",
            requirement: "^2.0.0",
            groups: ["dependencies"],
            source: { type: "registry", url: "https://registry.npmjs.org" }
          }],
          package_manager: "npm_and_yarn"
        )
      end

      context "if any of the versions is vulnerable" do
        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: "foo",
              package_manager: "npm_and_yarn",
              vulnerable_versions: [">=2.0.0 <2.0.3"],
              safe_versions: [">=1.0.0 <2.0.0", ">=2.0.3"]
            )
          ]
        end

        it "returns true" do
          expect(checker.vulnerable?).to eq(true)
        end
      end

      context "if none of the versions is vulnerable" do
        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: "foo",
              package_manager: "npm_and_yarn",
              vulnerable_versions: ["<1.0.0"],
              safe_versions: [">=1.0.0"]
            )
          ]
        end

        it "returns false" do
          expect(checker.vulnerable?).to eq(false)
        end
      end
    end
  end

  describe "#up_to_date?", :vcr do
    context "with no lockfile" do
      let(:dependency_files) { project_dependency_files("npm6/peer_dependency_typescript_no_lockfile") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "typescript",
          version: nil,
          requirements: [{
            requirement: "3.7",
            file: "package.json",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "returns false when there is a newer version available" do
        expect(checker.up_to_date?).to be_falsy
      end
    end

    context "with a latest version requirement" do
      let(:dependency_files) { project_dependency_files("npm8/latest_requirement") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: nil,
          requirements: [
            { file: "package.json", requirement: "latest", groups: [], source: nil }
          ],
          package_manager: "npm_and_yarn"
        )
      end

      it "is up to date because there's nothing to update" do
        expect(checker.up_to_date?).to be_truthy
      end
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }

      context "with no version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            requirements: [{
              file: "package.json",
              requirement: "^0.9.0",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to be_truthy }
      end
    end

    context "given an up-to-date dependency" do
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

      it { is_expected.to be_falsey }

      context "with no version" do
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

        context "and a requirement that exactly matches" do
          let(:requirement) { "^1.7.0" }
          it { is_expected.to be_falsey }
        end

        context "and a requirement that covers but doesn't exactly match" do
          let(:requirement) { "^1.6.0" }
          it { is_expected.to be_falsey }
        end
      end

      context "for a locked transitive security update", :vcr do
        let(:dependency_files) { project_dependency_files("npm8/locked_transitive_dependency") }
        let(:registry_listing_url) { "https://registry.npmjs.org/locked-transitive-dependency" }
        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: "@dependabot-fixtures/npm-transitive-dependency",
              package_manager: "npm_and_yarn",
              vulnerable_versions: ["< 1.0.1"]
            )
          ]
        end
        let(:dependency_version) { "1.0.0" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "@dependabot-fixtures/npm-transitive-dependency",
            version: dependency_version,
            requirements: [],
            package_manager: "npm_and_yarn"
          )
        end

        it "can't update without unlocking" do
          expect(subject).to eq(false)
        end

        it "allows full unlocking" do
          expect(checker.can_update?(requirements_to_unlock: :all)).to eq(true)
        end

        context "when the vulnerable transitive dependency is removed as a result of updating its parent" do
          let(:dependency_files) { project_dependency_files("npm8/locked_transitive_dependency_removed") }
          let(:registry_listing_url) { "https://registry.npmjs.org/locked_transitive_dependency_removed" }

          it "doesn't allow an update because removal has not been enabled" do
            expect(checker.can_update?(requirements_to_unlock: :all)).to eq(false)
          end
        end
      end

      context "when a transitive dependency is able to update without unlocking its parent but is still vulnerable",
              :vcr do
        let(:dependency_files) { project_dependency_files("npm8/transitive_dependency_locked_but_updateable") }
        let(:registry_listing_url) { "https://registry.npmjs.org/transitive-dependency-locked-but-updateable" }

        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: "@dependabot-fixtures/npm-transitive-dependency-with-more-versions",
              package_manager: "npm_and_yarn",
              vulnerable_versions: ["< 2.0.0"]
            )
          ]
        end
        let(:dependency_version) { "1.0.0" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "@dependabot-fixtures/npm-transitive-dependency-with-more-versions",
            version: dependency_version,
            requirements: [],
            package_manager: "npm_and_yarn"
          )
        end

        it "can't update without unlocking" do
          expect(subject).to eq(false)
        end

        it "allows full unlocking" do
          expect(checker.can_update?(requirements_to_unlock: :all)).to eq(true)
        end
      end
    end

    context "for a scoped package name" do
      before do
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
          to_return(
            status: 200,
            body: fixture("npm_responses", "etag.json")
          )
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep/1.7.0").
          to_return(status: 200)
        allow_any_instance_of(described_class::VersionResolver).
          to receive(:latest_resolvable_version).
          and_return(Gem::Version.new("1.7.0"))
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
      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
    subject { checker.latest_version }

    it "delegates to LatestVersionFinder" do
      expect(described_class::LatestVersionFinder).to receive(:new).with(
        dependency: dependency,
        credentials: credentials,
        dependency_files: dependency_files,
        ignored_versions: ignored_versions,
        raise_on_ignored: false,
        security_advisories: security_advisories
      ).and_call_original

      expect(checker.latest_version).to eq(Gem::Version.new("1.7.0"))
    end
    it "only hits the registry once" do
      checker.latest_version
      expect(WebMock).to have_requested(:get, registry_listing_url).once
    end

    context "with multiple requirements" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "preact",
          version: "0.1.0",
          package_manager: "npm_and_yarn",
          requirements: [
            {
              requirement: "^0.1.0",
              file: "package-lock.json",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            },
            {
              requirement: "^0.1.0",
              file: "yarn.lock",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.yarnpkg.com" }
            }
          ]
        )
      end

      before do
        stub_request(:get, "https://registry.npmjs.org/preact").
          and_return(status: 200, body: JSON.pretty_generate({}))
      end

      specify { expect { subject }.not_to raise_error }
    end

    context "with a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "is-number",
          version: current_version,
          requirements: [{
            requirement: req,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: ref
            }
          }],
          package_manager: "npm_and_yarn"
        )
      end
      let(:registry_listing_url) { "https://registry.npmjs.org/is-number" }
      let(:registry_response) do
        fixture("npm_responses", "is_number.json")
      end
      let(:current_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      before do
        git_url = "https://github.com/jonschlinkert/is-number.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: %w(x-access-token token)).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", upload_pack_fixture),
            headers: git_header
          )
        stub_request(:get, registry_listing_url + "/4.0.0").
          to_return(status: 200)

        repo_url = "https://api.github.com/repos/jonschlinkert/is-number"
        stub_request(:get, repo_url + "/compare/4.0.0...#{ref}").
          to_return(
            status: 200,
            body: commit_compare_response,
            headers: { "Content-Type" => "application/json" }
          )
      end
      let(:upload_pack_fixture) { "is-number" }
      let(:commit_compare_response) do
        fixture("github", "commit_compare_diverged.json")
      end

      context "with a branch" do
        let(:ref) { "master" }
        let(:req) { nil }

        it "fetches the latest SHA-1 hash of the head of the branch" do
          expect(checker.latest_version).
            to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end

        context "that doesn't exist" do
          let(:ref) { "nonexistent" }
          let(:req) { nil }

          it "fetches the latest SHA-1 hash of the head of the branch" do
            expect(checker.latest_version).to eq(current_version)
          end
        end

        context "for a dependency that doesn't have a release" do
          before do
            stub_request(:get, registry_listing_url).
              to_return(status: 404, body: "{}")
          end

          it "fetches the latest SHA-1 hash of the head of the branch" do
            expect(checker.latest_version).
              to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end
        end

        context "for a dependency that 405s" do
          before do
            stub_request(:get, registry_listing_url).
              to_return(status: 405, body: "{}")
          end

          it "fetches the latest SHA-1 hash of the head of the branch" do
            expect(checker.latest_version).
              to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end
        end
      end

      context "with a commit ref" do
        let(:ref) { "d5ac058" }
        let(:req) { nil }

        it "returns the current version" do
          expect(checker.latest_version).to eq(current_version)
        end
      end

      context "with a ref that looks like a version" do
        let(:ref) { "2.0.0" }
        let(:req) { nil }

        it "fetches the latest SHA-1 hash of the latest version tag" do
          expect(checker.latest_version).
            to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end

        context "but there are no tags" do
          let(:upload_pack_fixture) { "no_tags" }
          it { is_expected.to be_nil }
        end
      end

      context "with a requirement" do
        let(:ref) { "master" }
        let(:req) { "^2.0.0" }
        let(:current_version) { "2.0.2" }

        it "fetches the latest version tag" do
          expect(checker.latest_version).to eq(Gem::Version.new("4.0.0"))
        end

        context "but there are no tags" do
          let(:upload_pack_fixture) { "no_tags" }
          it { is_expected.to be_nil }
        end
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject { checker.lowest_security_fix_version }

    before do
      stub_request(:get, registry_listing_url + "/1.0.1").
        to_return(status: 200)
    end

    it "finds the lowest available non-vulnerable version" do
      expect(checker.lowest_security_fix_version).
        to eq(Gem::Version.new("1.0.1"))
    end

    context "with a security vulnerability" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "npm_and_yarn",
            vulnerable_versions: ["<= 1.2.0"]
          )
        ]
      end

      before do
        stub_request(:get, registry_listing_url + "/1.2.1").
          to_return(status: 200)
      end

      it "finds the lowest available non-vulnerable version" do
        is_expected.to eq(Gem::Version.new("1.2.1"))
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    it { is_expected.to eq(Gem::Version.new("1.7.0")) }

    context "for a sub-dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.1.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:registry_listing_url) { "https://registry.npmjs.org/acorn" }

      it "delegates to SubdependencyVersionResolver" do
        dummy_version_resolver =
          instance_double(described_class::SubdependencyVersionResolver)

        expect(described_class::SubdependencyVersionResolver).
          to receive(:new).
          with(
            dependency: dependency,
            credentials: credentials,
            dependency_files: dependency_files,
            ignored_versions: ignored_versions,
            latest_allowable_version: Gem::Version.new("1.7.0"),
            repo_contents_path: nil
          ).and_return(dummy_version_resolver)
        expect(dummy_version_resolver).
          to receive(:latest_resolvable_version).
          and_return(Gem::Version.new("5.7.3"))

        expect(checker.latest_resolvable_version).
          to eq(Gem::Version.new("5.7.3"))
      end
    end
  end

  describe "#preferred_resolvable_version" do
    subject { checker.preferred_resolvable_version }

    it { is_expected.to eq(Gem::Version.new("1.7.0")) }

    context "with a security vulnerability" do
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
      before do
        stub_request(:get, registry_listing_url + "/1.2.1").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.2.1")) }

      context "for a sub-dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "acorn",
            version: "5.1.1",
            requirements: [],
            package_manager: "npm_and_yarn"
          )
        end
        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: "rails",
              package_manager: "npm_and_yarn",
              vulnerable_versions: ["<= 5.2.0"]
            )
          ]
        end
        let(:registry_listing_url) { "https://registry.npmjs.org/acorn" }

        it "delegates to SubdependencyVersionResolver" do
          dummy_version_resolver =
            instance_double(described_class::SubdependencyVersionResolver)

          expect(described_class::SubdependencyVersionResolver).
            to receive(:new).
            with(
              dependency: dependency,
              credentials: credentials,
              dependency_files: dependency_files,
              ignored_versions: ignored_versions,
              latest_allowable_version: Gem::Version.new("1.7.0"),
              repo_contents_path: nil
            ).and_return(dummy_version_resolver)
          expect(dummy_version_resolver).
            to receive(:latest_resolvable_version).
            and_return(Gem::Version.new("5.7.3"))

          expect(checker.preferred_resolvable_version).
            to eq(Gem::Version.new("5.7.3"))
        end
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.latest_resolvable_version_with_no_unlock }

    context "with a non-git dependency" do
      let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
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

      it "delegates to LatestVersionFinder" do
        expect(described_class::LatestVersionFinder).to receive(:new).with(
          dependency: dependency,
          credentials: credentials,
          dependency_files: dependency_files,
          ignored_versions: ignored_versions,
          raise_on_ignored: false,
          security_advisories: security_advisories
        ).and_call_original

        expect(checker.latest_resolvable_version_with_no_unlock).
          to eq(Gem::Version.new("1.7.0"))
      end
    end

    context "for a sub-dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.1.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:registry_listing_url) { "https://registry.npmjs.org/acorn" }

      it "delegates to SubdependencyVersionResolver" do
        dummy_version_resolver =
          instance_double(described_class::SubdependencyVersionResolver)

        expect(described_class::SubdependencyVersionResolver).
          to receive(:new).
          with(
            dependency: dependency,
            credentials: credentials,
            dependency_files: dependency_files,
            ignored_versions: ignored_versions,
            latest_allowable_version: Gem::Version.new("1.7.0"),
            repo_contents_path: nil
          ).and_return(dummy_version_resolver)
        expect(dummy_version_resolver).
          to receive(:latest_resolvable_version).
          and_return(Gem::Version.new("5.7.3"))

        expect(checker.latest_resolvable_version_with_no_unlock).
          to eq(Gem::Version.new("5.7.3"))
      end
    end

    context "with a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "is-number",
          version: current_version,
          requirements: [{
            requirement: req,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: ref
            }
          }],
          package_manager: "npm_and_yarn"
        )
      end
      let(:current_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      before do
        git_url = "https://github.com/jonschlinkert/is-number.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: %w(x-access-token token)).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "is-number"),
            headers: git_header
          )
      end

      context "with a branch" do
        let(:ref) { "master" }
        let(:req) { nil }

        it "fetches the latest SHA-1 hash of the head of the branch" do
          expect(checker.latest_resolvable_version_with_no_unlock).
            to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end
      end

      context "with a ref that looks like a version" do
        let(:ref) { "2.0.0" }
        let(:req) { nil }

        it "fetches the latest SHA-1 hash of the latest version tag" do
          expect(checker.latest_resolvable_version_with_no_unlock).
            to eq(current_version)
        end
      end

      context "with a requirement" do
        let(:ref) { "master" }
        let(:req) { "^2.0.0" }

        it "fetches the latest SHA-1 hash of the latest version tag" do
          expect(checker.latest_resolvable_version_with_no_unlock).
            to eq(current_version)
        end

        context "and a numeric version" do
          let(:current_version) { "2.0.2" }

          it "return a numeric version" do
            expect(checker.latest_resolvable_version_with_no_unlock).
              to eq(Gem::Version.new("2.0.2"))
          end
        end
      end
    end
  end

  describe "#latest_resolvable_previous_version" do
    let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
    let(:updated_version) { Gem::Version.new("1.7.0") }
    subject(:latest_resolvable_previous_version) do
      checker.latest_resolvable_previous_version(updated_version)
    end

    it "delegates to VersionResolver" do
      dummy_version_resolver =
        instance_double(described_class::VersionResolver)

      expect(described_class::VersionResolver).
        to receive(:new).
        with(
          dependency: dependency,
          credentials: credentials,
          dependency_files: dependency_files,
          latest_version_finder: described_class::LatestVersionFinder,
          latest_allowable_version: updated_version,
          repo_contents_path: nil
        ).and_return(dummy_version_resolver)
      expect(dummy_version_resolver).
        to receive(:latest_resolvable_previous_version).
        with(updated_version).
        and_return(Gem::Version.new("1.6.0"))

      expect(latest_resolvable_previous_version).
        to eq(Gem::Version.new("1.6.0"))
    end
  end

  describe "#updated_requirements" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: dependency_version,
        requirements: dependency_requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "package.json",
        requirement: "^1.0.0",
        groups: [],
        source: nil
      }]
    end

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: dependency_requirements,
          updated_source: nil,
          latest_resolvable_version: "1.7.0",
          update_strategy: :bump_versions
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [{
            file: "package.json",
            requirement: "^1.7.0",
            groups: [],
            source: nil
          }]
        )
    end

    context "with a security vulnerability" do
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
      before do
        stub_request(:get, registry_listing_url + "/1.2.1").
          to_return(status: 200)
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            updated_source: nil,
            latest_resolvable_version: "1.2.1",
            update_strategy: :bump_versions
          ).
          and_call_original
        expect(checker.updated_requirements).
          to eq(
            [{
              file: "package.json",
              requirement: "^1.2.1",
              groups: [],
              source: nil
            }]
          )
      end
    end

    context "when a requirements_update_strategy has been specified" do
      let(:checker) do
        described_class.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: security_advisories,
          requirements_update_strategy: :bump_versions_if_necessary
        )
      end

      it "uses the specified requirements_update_strategy" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            updated_source: nil,
            latest_resolvable_version: "1.7.0",
            update_strategy: :bump_versions_if_necessary
          ).
          and_call_original
        expect(checker.updated_requirements).
          to eq(
            [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }]
          )
      end
    end

    context "with a library (that has a lockfile)" do
      # We've already stubbed hitting the registry for etag (since it's also
      # the dependency we're checking in this spec)
      let(:dependency_files) { project_dependency_files("npm6/etag_no_lockfile") }

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            updated_source: nil,
            latest_resolvable_version: "1.7.0",
            update_strategy: :widen_ranges
          ).
          and_call_original
        expect(checker.updated_requirements).
          to eq(
            [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }]
          )
      end
    end

    context "with a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "is-number",
          version: dependency_version,
          requirements: dependency_requirements,
          package_manager: "npm_and_yarn"
        )
      end
      let(:dependency_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      let(:dependency_requirements) do
        [{
          requirement: "^2.0.0",
          file: "package.json",
          groups: ["devDependencies"],
          source: {
            type: "git",
            url: "https://github.com/jonschlinkert/is-number",
            branch: nil,
            ref: "master"
          }
        }]
      end
      let(:registry_listing_url) { "https://registry.npmjs.org/is-number" }
      let(:registry_response) do
        fixture("npm_responses", "is_number.json")
      end
      let(:commit_compare_response) do
        fixture("github", "commit_compare_diverged.json")
      end

      before do
        git_url = "https://github.com/jonschlinkert/is-number.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: %w(x-access-token token)).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "is-number"),
            headers: git_header
          )
        repo_url = "https://api.github.com/repos/jonschlinkert/is-number"
        stub_request(:get, repo_url + "/compare/4.0.0...master").
          to_return(
            status: 200,
            body: commit_compare_response,
            headers: { "Content-Type" => "application/json" }
          )
        stub_request(:get, registry_listing_url + "/4.0.0").
          to_return(status: 200)
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            updated_source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: "master"
            },
            latest_resolvable_version: "4.0.0",
            update_strategy: :bump_versions
          ).
          and_call_original
        expect(checker.updated_requirements).
          to eq(
            [{
              file: "package.json",
              requirement: "^4.0.0",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://github.com/jonschlinkert/is-number",
                branch: nil,
                ref: "master"
              }
            }]
          )
      end

      context "with a version that looks like a number" do
        let(:dependency_version) { "0.0.0" }

        it "delegates to the RequirementsUpdater" do
          expect(described_class::RequirementsUpdater).
            to receive(:new).
            with(
              requirements: dependency_requirements,
              updated_source: {
                type: "git",
                url: "https://github.com/jonschlinkert/is-number",
                branch: nil,
                ref: "master"
              },
              latest_resolvable_version: "4.0.0",
              update_strategy: :bump_versions
            ).
            and_call_original
          expect(checker.updated_requirements).
            to eq(
              [{
                file: "package.json",
                requirement: "^4.0.0",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/jonschlinkert/is-number",
                  branch: nil,
                  ref: "master"
                }
              }]
            )
        end
      end
    end

    context "updating a deprecated dependency with a peer requirement" do
      let(:dependency_files) { project_dependency_files("npm6/peer_dependency_no_lockfile") }
      let(:registry_listing_url) { "https://registry.npmjs.org/react-dom" }
      let(:registry_response) do
        fixture("npm_responses", "peer_dependency_deprecated.json")
      end
      let(:dependency_requirements) do
        [{
          file: "package.json",
          requirement: "^15.2.0",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "react-dom",
          version: "15.2.0",
          package_manager: "npm_and_yarn",
          requirements: dependency_requirements
        )
      end

      before do
        stub_request(:get, registry_listing_url + "/16.3.1").
          to_return(status: 200)
        stub_request(:get, "https://registry.npmjs.org/test").
          to_return(status: 200)
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            updated_source: nil,
            latest_resolvable_version: nil,
            update_strategy: :widen_ranges
          ).
          and_call_original

        # No change in updated_requirements
        expect(checker.updated_requirements).
          to eq(dependency_requirements)
      end
    end

    context "with multiple requirements" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@org/etag",
          version: "1.0",
          requirements: [
            {
              file: "package.json",
              requirement: "^1.0",
              groups: [],
              source: {
                type: "registry",
                url: "https://registry.npmjs.org"
              }
            },
            {
              file: "package.json",
              requirement: "^1.0",
              groups: [],
              source: {
                type: "registry",
                url: "https://npm.fury.io/dependabot"
              }
            }
          ],
          package_manager: "npm_and_yarn"
        )
      end

      before do
        stub_request(:get, "https://npm.fury.io/dependabot/@org%2Fetag").
          and_return(status: 200, body: JSON.pretty_generate({}))
      end

      it "prefers to private registry source" do
        expect(checker.updated_requirements.first).to eq(
          {
            file: "package.json",
            groups: [],
            requirement: "^1.0",
            source: {
              type: "registry",
              url: "https://npm.fury.io/dependabot"
            }
          }
        )
      end
    end
  end

  context "#updated_dependencies_after_full_unlock" do
    let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: dependency_version,
        requirements: dependency_requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "package.json",
        requirement: "^1.0.0",
        groups: [],
        source: nil
      }]
    end

    it "delegates to the VersionResolver" do
      dummy_version_resolver =
        instance_double(described_class::VersionResolver)

      expect(described_class::VersionResolver).
        to receive(:new).
        with(
          dependency: dependency,
          credentials: credentials,
          dependency_files: dependency_files,
          latest_version_finder: described_class::LatestVersionFinder,
          latest_allowable_version: Gem::Version.new("1.7.0"),
          repo_contents_path: nil
        ).and_return(dummy_version_resolver)
      expect(dummy_version_resolver).
        to receive(:dependency_updates_from_full_unlock).
        and_return(
          [{
            dependency: Dependabot::Dependency.new(
              name: "etag",
              version: nil,
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "^1.6.0",
                groups: ["dependencies"],
                source: nil
              }]
            ),
            version: Dependabot::NpmAndYarn::Version.new("1.7.0"),
            previous_version: nil
          }]
        )

      expect(checker.send(:updated_dependencies_after_full_unlock).first).
        to eq(
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.7.0",
            package_manager: "npm_and_yarn",
            previous_version: nil,
            requirements: [{
              file: "package.json",
              requirement: "^1.7.0",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^1.6.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        )
    end

    # Dependency doesn't consider metadata as part of equality checks
    # so this allows us to check that the metadata is updated in tests.
    RSpec::Matchers.define :including_metadata do |expected|
      match do |actual|
        actual == expected && actual.metadata == expected.metadata
      end
    end

    def contain_exactly_including_metadata(*expected)
      contain_exactly(*expected.map { |e| including_metadata(e) })
    end

    def eq_including_metadata(expected_array)
      eq(expected_array).and contain_exactly_including_metadata(*expected_array)
    end

    context "for a security update for a locked transitive dependency" do
      let(:dependency_files) { project_dependency_files("npm8/locked_transitive_dependency") }
      let(:registry_listing_url) { "https://registry.npmjs.org/locked-transitive-dependency" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "@dependabot-fixtures/npm-transitive-dependency",
            package_manager: "npm_and_yarn",
            vulnerable_versions: ["< 1.0.1"]
          )
        ]
      end
      let(:dependency_version) { "1.0.0" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@dependabot-fixtures/npm-transitive-dependency",
          version: dependency_version,
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it "correctly updates the transitive dependency" do
        expect(checker.send(:updated_dependencies_after_full_unlock)).
          to eq_including_metadata([
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-transitive-dependency",
              version: "1.0.1",
              package_manager: "npm_and_yarn",
              previous_version: "1.0.0",
              requirements: [],
              previous_requirements: [],
              metadata: { information_only: true }
            ),
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-parent-dependency",
              version: "2.0.2",
              package_manager: "npm_and_yarn",
              previous_version: "2.0.0",
              requirements: [{
                file: "package.json",
                requirement: "2.0.2",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              previous_requirements: [{
                file: "package.json",
                requirement: "2.0.0",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }]
            )
          ])
      end

      context "when a transitive dependency is locked by an intermediate transitive dependency" do
        let(:dependency_files) { project_dependency_files("npm8/transitive_dependency_locked_by_intermediate") }
        let(:registry_listing_url) { "https://registry.npmjs.org/transitive-dependency-locked-by-intermediate" }

        it "correctly updates the transitive dependency" do
          expect(checker.send(:updated_dependencies_after_full_unlock)).to eq_including_metadata([
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-transitive-dependency",
              package_manager: "npm_and_yarn",
              previous_requirements: [],
              previous_version: "1.0.0",
              requirements: [],
              version: "1.0.1",
              metadata: { information_only: true }
            ),
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-intermediate-dependency",
              package_manager: "npm_and_yarn",
              previous_requirements: [],
              previous_version: "0.0.1",
              requirements: [],
              version: "0.0.2"
            )
          ])
        end
      end

      context "when a transitive dependency is locked by multiple top-level dependencies" do
        let(:dependency_files) { project_dependency_files("npm8/transitive_dependency_locked_by_multiple") }
        let(:registry_listing_url) { "https://registry.npmjs.org/transitive-dependency-locked-by-multiple" }

        it "correctly updates the transitive dependency" do
          expect(checker.send(:updated_dependencies_after_full_unlock)).to contain_exactly_including_metadata(
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-parent-dependency",
              package_manager: "npm_and_yarn",
              previous_requirements: [{
                requirement: "2.0.1",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              previous_version: "2.0.1",
              requirements: [{
                requirement: "2.0.2",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              version: "2.0.2"
            ),
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-parent-dependency-2",
              package_manager: "npm_and_yarn",
              previous_requirements: [{
                requirement: "2.1.0",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              previous_version: "2.1.0",
              requirements: [{
                requirement: "2.1.1",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              version: "2.1.1"
            ),
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-parent-dependency-3",
              package_manager: "npm_and_yarn",
              previous_requirements: [{
                requirement: "2.0.0",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              previous_version: "2.0.0",
              requirements: [{
                requirement: "3.0.0",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              version: "3.0.0"
            ),
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-transitive-dependency",
              package_manager: "npm_and_yarn",
              previous_requirements: [],
              previous_version: "1.0.0",
              requirements: [],
              version: "1.0.1",
              metadata: { information_only: true }
            )
          )
        end
      end

      context "when the vulnerable transitive dependency is removed as a result of updating its parent" do
        let(:dependency_files) { project_dependency_files("npm8/locked_transitive_dependency_removed") }
        let(:registry_listing_url) { "https://registry.npmjs.org/locked-transitive-dependency-removed" }
        let(:options) do
          {
            npm_transitive_dependency_removal: true
          }
        end

        it "correctly updates the parent dependency and removes the transitive because removal is enabled" do
          expect(checker.send(:updated_dependencies_after_full_unlock)).to contain_exactly_including_metadata(
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-transitive-dependency",
              package_manager: "npm_and_yarn",
              previous_requirements: [],
              previous_version: "1.0.0",
              requirements: [],
              removed: true,
              metadata: { information_only: true }
            ),
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-remove-dependency",
              package_manager: "npm_and_yarn",
              previous_requirements: [{
                requirement: "10.0.0",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              previous_version: "10.0.0",
              requirements: [{
                requirement: "10.0.1",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              version: "10.0.1"
            )
          )
        end
      end

      context "when a transitive dependency is able to update without unlocking its parent but is still vulnerable" do
        let(:dependency_files) { project_dependency_files("npm8/transitive_dependency_locked_but_updateable") }
        let(:registry_listing_url) { "https://registry.npmjs.org/transitive-dependency-locked-but-updateable" }

        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: "@dependabot-fixtures/npm-transitive-dependency-with-more-versions",
              package_manager: "npm_and_yarn",
              vulnerable_versions: ["< 2.0.0"]
            )
          ]
        end
        let(:dependency_version) { "1.0.0" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "@dependabot-fixtures/npm-transitive-dependency-with-more-versions",
            version: dependency_version,
            requirements: [],
            package_manager: "npm_and_yarn"
          )
        end

        it "correctly updates the transitive dependency by unlocking the parent" do
          expect(checker.send(:updated_dependencies_after_full_unlock)).to eq_including_metadata([
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-transitive-dependency-with-more-versions",
              package_manager: "npm_and_yarn",
              previous_requirements: [],
              previous_version: "1.0.0",
              requirements: [],
              version: "2.0.0",
              metadata: { information_only: true }
            ),
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-parent-dependency-with-more-versions",
              package_manager: "npm_and_yarn",
              previous_requirements: [{
                requirement: "^1.0.0",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              previous_version: "1.0.0",
              requirements: [{
                requirement: "^1.0.0",
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              version: "1.0.1"
            )
          ])
        end
      end
    end
  end

  describe "#conflicting_dependencies" do
    let(:registry_listing_url) { "https://registry.npmjs.org/locked-transitive-dependency" }
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
        name: "@dependabot-fixtures/npm-transitive-dependency",
        version: dependency_version,
        requirements: [],
        package_manager: "npm_and_yarn"
      )
    end

    context "with a conflicting dependency" do
      let(:dependency_files) { project_dependency_files("npm8/locked_transitive_dependency") }
      let(:dependency_version) { "1.0.0" }
      let(:target_version) { Dependabot::NpmAndYarn::Version.new("1.0.1") }

      it "delegates to the ConflictingDependencyResolver and explains the conflict", :vcr do
        expect(described_class::ConflictingDependencyResolver).
          to receive(:new).
          with(
            dependency_files: dependency_files,
            credentials: credentials
          ).and_call_original

        conflicting_dependencies_result = checker.send(:conflicting_dependencies)

        expect(conflicting_dependencies_result.count).to eq(1)
        expect(conflicting_dependencies_result.first).
          to eq(
            "explanation" => "@dependabot-fixtures/npm-parent-dependency@2.0.0 requires " \
                             "@dependabot-fixtures/npm-transitive-dependency@1.0.0 via " \
                             "@dependabot-fixtures/npm-intermediate-dependency@0.0.1",
            "name" => "@dependabot-fixtures/npm-intermediate-dependency",
            "requirement" => "1.0.0",
            "version" => "0.0.1"
          )
      end
    end

    context "with a locking parent dependency and an unsatisfiable vulnerablity" do
      let(:dependency_files) { project_dependency_files("npm8/transitive_dependency_locked_by_parent") }
      let(:dependency_version) { "1.0.0" }
      let(:target_version) { Dependabot::NpmAndYarn::Version.new("1.0.1") }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "@dependabot-fixtures/npm-transitive-dependency",
            package_manager: "npm_and_yarn",
            vulnerable_versions: ["< 1.0.1"]
          )
        ]
      end

      it "delegates to the ConflictingDependencyResolver and VulnerabilityAuditor and explains the conflict", :vcr do
        expect(described_class::ConflictingDependencyResolver).
          to receive(:new).
          with(
            dependency_files: dependency_files,
            credentials: credentials
          ).and_call_original

        expect(described_class::VulnerabilityAuditor).
          to receive(:new).
          with(
            dependency_files: dependency_files,
            credentials: credentials,
            allow_removal: false
          ).and_call_original

        checker.send(:vulnerability_audit)
        conflicting_dependencies_result = checker.send(:conflicting_dependencies)

        expect(conflicting_dependencies_result.count).to eq(2)

        expect(conflicting_dependencies_result.first).
          to eq(
            "explanation" => "@dependabot-fixtures/npm-parent-dependency-5@1.0.0 requires " \
                             "@dependabot-fixtures/npm-transitive-dependency@1.0.0 via " \
                             "@dependabot-fixtures/npm-intermediate-dependency@0.0.1",
            "name" => "@dependabot-fixtures/npm-intermediate-dependency",
            "requirement" => "1.0.0",
            "version" => "0.0.1"
          )

        expect(conflicting_dependencies_result.last).
          to eq(
            "dependency_name" => "@dependabot-fixtures/npm-transitive-dependency",
            "explanation" => "No patched version available for @dependabot-fixtures/npm-transitive-dependency",
            "fix_available" => false,
            "fix_updates" => [],
            "top_level_ancestors" => []
          )
      end
    end

    context "with a conflicting dependency and an unsatisfiable vulnerablity" do
      let(:dependency_files) { project_dependency_files("npm8/locked_transitive_dependency") }
      let(:dependency_version) { "1.0.0" }
      let(:target_version) { Dependabot::NpmAndYarn::Version.new("1.0.1") }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "@dependabot-fixtures/npm-transitive-dependency",
            package_manager: "npm_and_yarn",
            vulnerable_versions: ["< 1.0.2"]
          )
        ]
      end

      it "delegates to the ConflictingDependencyResolver and VulnerabilityAuditor and explains the conflict", :vcr do
        expect(described_class::ConflictingDependencyResolver).
          to receive(:new).
          with(
            dependency_files: dependency_files,
            credentials: credentials
          ).and_call_original

        expect(described_class::VulnerabilityAuditor).
          to receive(:new).
          with(
            dependency_files: dependency_files,
            credentials: credentials,
            allow_removal: false
          ).and_call_original

        checker.send(:vulnerability_audit)
        conflicting_dependencies_result = checker.send(:conflicting_dependencies)

        expect(conflicting_dependencies_result.count).to eq(2)

        expect(conflicting_dependencies_result.first).
          to eq(
            "explanation" => "@dependabot-fixtures/npm-parent-dependency@2.0.0 requires " \
                             "@dependabot-fixtures/npm-transitive-dependency@1.0.0 via " \
                             "@dependabot-fixtures/npm-intermediate-dependency@0.0.1",
            "name" => "@dependabot-fixtures/npm-intermediate-dependency",
            "requirement" => "1.0.0",
            "version" => "0.0.1"
          )

        expect(conflicting_dependencies_result.last).
          to eq(
            "dependency_name" => "@dependabot-fixtures/npm-transitive-dependency",
            "explanation" => "No patched version available for @dependabot-fixtures/npm-transitive-dependency",
            "fix_available" => false,
            "fix_updates" => [],
            "top_level_ancestors" => []
          )
      end
    end
  end

  context "when types dependency specified" do
    let(:registry_listing_url) { "https://registry.npmjs.org/jquery" }
    let(:registry_response) do
      fixture("npm_responses", "jquery.json")
    end
    let(:types_listing_url) { "https://registry.yarnpkg.com/@types%2Fjquery" }
    let(:types_response) do
      fixture("npm_responses", "types_jquery.json")
    end
    before do
      stub_request(:get, registry_listing_url).
        to_return(status: 200, body: registry_response)
      stub_request(:get, registry_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, registry_listing_url + "/3.6.0").
        to_return(status: 200)
      stub_request(:get, types_listing_url).
        to_return(status: 200, body: types_response)
      stub_request(:get, types_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, types_listing_url + "/3.3.10").
        to_return(status: 200)
      stub_request(:get, types_listing_url + "/3.5.14").
        to_return(status: 200)
    end
    let(:dependency_files) { project_dependency_files("yarn/ts_fully_typed") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "jquery",
        version: "3.4",
        requirements: dependency_requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "yarn.lock",
        requirement: "3.4",
        groups: [],
        source: nil
      }]
    end
    it "returns both dependencies for update" do
      updated_deps = checker.updated_dependencies(requirements_to_unlock: :all)
      expect(updated_deps.first.version).to eq("3.6.0")
      expect(updated_deps.length).to eq(2)
      expect(updated_deps.last.version).to eq("3.5.14")
    end
    context "with a security advisory" do
      before do
        stub_request(:get, registry_listing_url + "/3.4.1").
          to_return(status: 200)
      end
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "jquery",
            package_manager: "npm_and_yarn",
            vulnerable_versions: ["<=3.4.0"]
          )
        ]
      end
      it "returns both dependencies for update" do
        updated_deps = checker.updated_dependencies(requirements_to_unlock: :own)
        expect(updated_deps.first.version).to eq("3.4.1")
        updated_deps = checker.updated_dependencies(requirements_to_unlock: :all)
        expect(updated_deps.length).to eq(2)
        expect(updated_deps.last.version).to eq("3.5.14")
      end
    end
  end
  context "if types dependency not specified" do
    let(:registry_listing_url) { "https://registry.npmjs.org/jquery" }
    let(:registry_response) do
      fixture("npm_responses", "jquery.json")
    end
    before do
      stub_request(:get, registry_listing_url).
        to_return(status: 200, body: registry_response)
      stub_request(:get, registry_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, registry_listing_url + "/3.6.0").
        to_return(status: 200)
    end
    let(:dependency_files) { project_dependency_files("yarn/ts_missing_types") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "jquery",
        version: "3.4",
        requirements: dependency_requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "package.json",
        requirement: "^3.4",
        groups: [],
        source: nil
      }]
    end
    it "returns only one dependency" do
      updated_deps = checker.updated_dependencies(requirements_to_unlock: :own)
      expect(updated_deps.first.version).to eq("3.6.0")
      expect(updated_deps.length).to eq(1)
    end
  end
  context "when no update to @types available" do
    let(:registry_listing_url) { "https://registry.npmjs.org/jquery" }
    let(:registry_response) do
      fixture("npm_responses", "jquery.json")
    end
    let(:types_listing_url) { "https://registry.yarnpkg.com/@types%2Fjquery" }
    let(:types_response) do
      fixture("npm_responses", "types_jquery.json")
    end
    before do
      stub_request(:get, registry_listing_url).
        to_return(status: 200, body: registry_response)
      stub_request(:get, registry_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, registry_listing_url + "/3.6.0").
        to_return(status: 200)
      stub_request(:get, types_listing_url).
        to_return(status: 200, body: types_response)
      stub_request(:get, types_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, types_listing_url + "/3.5.14").
        to_return(status: 200)
    end
    let(:dependency_files) { project_dependency_files("yarn/ts_no_type_update") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "jquery",
        version: "3.5",
        requirements: dependency_requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "package.json",
        requirement: "^3.5",
        groups: [],
        source: nil
      }]
    end
    it "only updates original package" do
      updated_deps = checker.updated_dependencies(requirements_to_unlock: :all)
      expect(updated_deps.first.version).to eq("3.6.0")
      expect(updated_deps.length).to eq(1)
    end
  end
  context "if types is a normal dependency" do
    let(:registry_listing_url) { "https://registry.npmjs.org/node-forge" }
    let(:registry_response) do
      fixture("npm_responses", "node-forge.json")
    end
    let(:types_listing_url) { "https://registry.yarnpkg.com/@types%2Fnode-forge" }
    let(:types_response) do
      fixture("npm_responses", "types_node-forge.json")
    end
    before do
      stub_request(:get, registry_listing_url).
        to_return(status: 200, body: registry_response)
      stub_request(:get, registry_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, registry_listing_url + "/1.3.1").
        to_return(status: 200)
      stub_request(:get, types_listing_url).
        to_return(status: 200, body: types_response)
      stub_request(:get, types_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, types_listing_url + "/1.0.0").
        to_return(status: 200)
      stub_request(:get, types_listing_url + "/1.0.1").
        to_return(status: 200)
    end
    let(:dependency_files) { project_dependency_files("yarn/ts_fully_typed") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "node-forge",
        version: "1.0.0",
        requirements: dependency_requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "package.json",
        requirement: "^1.0.0",
        groups: [],
        source: nil
      }]
    end
    it "returns 2 dependencies to update" do
      updated_deps = checker.updated_dependencies(requirements_to_unlock: :all)
      expect(updated_deps.first.version).to eq("1.3.1")
      expect(updated_deps.length).to eq(2)
      expect(updated_deps.last.version).to eq("1.0.1")
    end
  end
  context "if types dependency is checked, but updated original package exists" do
    let(:registry_listing_url) { "https://registry.yarnpkg.com/node-forge" }
    let(:registry_response) do
      fixture("npm_responses", "node-forge.json")
    end
    let(:types_listing_url) { "https://registry.npmjs.org/@types%2Fnode-forge" }
    let(:types_response) do
      fixture("npm_responses", "types_node-forge.json")
    end
    before do
      stub_request(:get, registry_listing_url).
        to_return(status: 200, body: registry_response)
      stub_request(:get, registry_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, registry_listing_url + "/1.3.1").
        to_return(status: 200)
      stub_request(:get, types_listing_url).
        to_return(status: 200, body: types_response)
      stub_request(:get, types_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, types_listing_url + "/1.0.0").
        to_return(status: 200)
      stub_request(:get, types_listing_url + "/1.0.1").
        to_return(status: 200)
    end
    let(:dependency_files) { project_dependency_files("yarn/ts_fully_typed") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "@types/node-forge",
        version: "1.0.0",
        requirements: dependency_requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "package.json",
        requirement: "^1.0.0",
        groups: [],
        source: nil
      }]
    end
    it "returns 0 dependencies to update" do
      updated_deps = checker.updated_dependencies(requirements_to_unlock: :all)
      expect(updated_deps.length).to eq(0)
    end
  end
  context "if yarn berry subdependency" do
    let(:project_name) { "yarn_berry/subdependency" }
    let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
    let(:registry_listing_url) { "https://registry.npmjs.org/is-stream" }
    let(:registry_response) do
      fixture("npm_responses", "is-stream.json")
    end
    before do
      stub_request(:get, registry_listing_url).
        to_return(status: 200, body: registry_response)
      stub_request(:get, registry_listing_url + "/latest").
        to_return(status: 200, body: "{}")
      stub_request(:get, registry_listing_url + "/3.0.0").
        to_return(status: 200)
    end
    let(:dependency_files) { project_dependency_files("yarn_berry/subdependency") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "is-stream",
        version: "1.0.1",
        requirements: [],
        package_manager: "npm_and_yarn"
      )
    end
    it "returns 1 dependencies to update to the correct version" do
      updated_deps = checker.updated_dependencies(requirements_to_unlock: :own)
      expect(updated_deps.length).to eq(1)
      expect(updated_deps[0].version).to eq("1.1.0")
      expect(updated_deps[0].name).to eq("is-stream")
    end
  end
end
