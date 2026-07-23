# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/cargo/update_checker"
require "dependabot/cargo/file_parser"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/requirements_update_strategy"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Cargo::UpdateChecker do
  let(:dependency_version) { "0.1.38" }
  let(:dependency_name) { "time" }
  let(:requirements) do
    [{ file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "cargo"
    )
  end
  let(:lockfile_fixture_name) { "bare_version_specified" }
  let(:manifest_fixture_name) { "bare_version_specified" }
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Cargo.toml",
        content: fixture("manifests", manifest_fixture_name)
      ),
      Dependabot::DependencyFile.new(
        name: "Cargo.lock",
        content: fixture("lockfiles", lockfile_fixture_name)
      )
    ]
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:requirements_update_strategy) { nil }
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:update_cooldown) { nil }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      requirements_update_strategy: requirements_update_strategy,
      update_cooldown: update_cooldown
    )
  end
  let(:crates_fixture_name) { "#{dependency_name}.json" }
  let(:crates_response) { fixture("crates_io_responses", crates_fixture_name) }
  let(:crates_url) { "https://crates.io/api/v1/crates/#{dependency_name}" }

  before do
    stub_request(:get, crates_url).to_return(status: 200, body: crates_response)
  end

  it_behaves_like "an update checker"

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "when given an up-to-date dependency" do
      let(:dependency_version) { "0.1.40" }

      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it { is_expected.to eq(Gem::Version.new("0.1.40")) }

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 0.1.40, < 2.0"] }

      it { is_expected.to eq(Gem::Version.new("0.1.39")) }
    end

    context "with a git dependency" do
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: nil
          }
        }]
      end

      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .with(basic_auth: %w(x-access-token token))
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      it { is_expected.to eq("47afd3c09c6583afdf4083fc9644f6f64172c8f8") }

      context "with a version-like tag" do
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: nil,
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: "0.1.3"
            }
          }]
        end

        # The SHA of the next version tag
        it { is_expected.to eq("83141b376b93484341c68fbca3ca110ae5cd2708") }

        context "with a cooldown period configured" do
          let(:update_cooldown) do
            Dependabot::Package::ReleaseCooldownOptions.new(default_days: 90)
          end

          before do
            allow(checker.send(:git_commit_checker))
              .to receive(:refs_for_tag_with_detail)
              .and_return(
                [
                  Dependabot::GitTagWithDetail.new(tag: "0.1.3", release_date: "2018-01-02"),
                  Dependabot::GitTagWithDetail.new(
                    tag: "1.0.0",
                    release_date: Time.now.strftime("%Y-%m-%d")
                  )
                ]
              )
          end

          it "skips the version tag still within its cooldown window" do
            expect(checker.latest_version)
              .to eq("d5094c7e9456f2965dec20de671094a98c6929c2")
          end

          context "when there is no cooldown (e.g. a security update)" do
            let(:update_cooldown) { nil }

            it "uses the latest version tag" do
              expect(checker.latest_version)
                .to eq("83141b376b93484341c68fbca3ca110ae5cd2708")
            end
          end
        end
      end

      context "with a non-version tag" do
        let(:dependency_version) { "gitsha" }
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: nil,
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: "something"
            }
          }]
        end

        it { is_expected.to eq(dependency_version) }
      end
    end

    context "with a git subdependency" do
      let(:manifest_fixture_name) { "git_subdependency" }
      let(:lockfile_fixture_name) { "git_subdependency" }

      let(:dependency_name) { "cranelift-bforest" }
      let(:dependency_version) { "ede366644f3777d43448367df1af86e52c21660b" }
      let(:requirements) { [] }
      let(:crates_response) { nil }

      it { is_expected.to be_nil }
    end

    context "with a path dependency" do
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: { type: "path" }
        }]
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { checker.lowest_security_fix_version }

    it "finds the lowest available non-vulnerable version" do
      expect(lowest_security_fix_version).to eq(Gem::Version.new("0.1.39"))
    end

    context "with a security vulnerability" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "cargo",
            vulnerable_versions: ["<= 0.1.39"]
          )
        ]
      end

      it "finds the lowest available non-vulnerable version" do
        expect(lowest_security_fix_version).to eq(Gem::Version.new("0.1.40"))
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "delegates to VersionResolver" do
      expect(Dependabot::Cargo::UpdateChecker::VersionResolver)
        .to receive(:new)
        .and_call_original
      expect(checker.latest_resolvable_version)
        .to eq(Gem::Version.new("0.1.40"))
    end

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 0.1.40, < 2.0"] }

      it { is_expected.to eq(Gem::Version.new("0.1.39")) }
    end

    context "when all versions are being ignored" do
      let(:ignored_versions) { [">= 0"] }
      let(:raise_on_ignored) { true }

      it "raises an error" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::AllVersionsIgnored)
      end
    end

    context "with a git dependency" do
      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .with(basic_auth: %w(x-access-token token))
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:manifest_fixture_name) { "git_dependency" }
      let(:lockfile_fixture_name) { "git_dependency" }
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: source
        }]
      end
      let(:source) do
        {
          type: "git",
          url: "https://github.com/BurntSushi/utf8-ranges",
          branch: nil,
          ref: nil
        }
      end

      it { is_expected.to eq("be9b8dfcaf449453cbf83ac85260ee80323f4f77") }

      context "with a tag" do
        let(:manifest_fixture_name) { "git_dependency_with_tag" }
        let(:lockfile_fixture_name) { "git_dependency_with_tag" }
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: "0.1.3"
          }
        end

        # The SHA of the next version tag
        it { is_expected.to eq("83141b376b93484341c68fbca3ca110ae5cd2708") }
      end

      context "with an ssh URL" do
        let(:manifest_fixture_name) { "git_dependency_ssh" }
        let(:lockfile_fixture_name) { "git_dependency_ssh" }
        let(:source) do
          {
            type: "git",
            url: "ssh://git@github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: nil
          }
        end

        it { is_expected.to eq("be9b8dfcaf449453cbf83ac85260ee80323f4f77") }
      end
    end

    context "with a git subdependency" do
      let(:manifest_fixture_name) { "git_subdependency" }
      let(:lockfile_fixture_name) { "git_subdependency" }

      let(:dependency_name) { "cranelift-bforest" }
      let(:dependency_version) { "ede366644f3777d43448367df1af86e52c21660b" }
      let(:requirements) { [] }
      let(:crates_response) { nil }

      it { is_expected.to be_nil }
    end
  end

  describe "#preferred_resolvable_version" do
    subject { checker.preferred_resolvable_version }

    it { is_expected.to eq(Gem::Version.new("0.1.40")) }

    context "with an insecure version" do
      let(:dependency_version) { "0.1.38" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "cargo",
            vulnerable_versions: ["<= 0.1.38"]
          )
        ]
      end

      it { is_expected.to eq(Gem::Version.new("0.1.39")) }
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.send(:latest_resolvable_version_with_no_unlock) }

    let(:dependency_name) { "regex" }
    let(:dependency_version) { "0.1.41" }
    let(:requirements) do
      [{
        file: "Cargo.toml",
        requirement: "0.1.41",
        groups: ["dependencies"],
        source: nil
      }]
    end

    it { is_expected.to eq(Gem::Version.new("0.1.80")) }

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 0.1.60, < 2.0"] }

      it { is_expected.to eq(Gem::Version.new("0.1.59")) }
    end

    context "with a git dependency" do
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:manifest_fixture_name) { "git_dependency" }
      let(:lockfile_fixture_name) { "git_dependency" }
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: source
        }]
      end
      let(:source) do
        {
          type: "git",
          url: "https://github.com/BurntSushi/utf8-ranges",
          branch: nil,
          ref: nil
        }
      end

      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .with(basic_auth: %w(x-access-token token))
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      it { is_expected.to eq("be9b8dfcaf449453cbf83ac85260ee80323f4f77") }

      context "with a tag" do
        let(:manifest_fixture_name) { "git_dependency_with_tag" }
        let(:lockfile_fixture_name) { "git_dependency_with_tag" }
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: "0.1.3"
          }
        end

        it { is_expected.to eq(dependency_version) }
      end
    end

    context "with a path dependency" do
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: { type: "path" }
        }]
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#updated_requirements" do
    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater)
        .to receive(:new)
        .with(
          requirements: requirements,
          updated_source: nil,
          target_version: "0.1.40",
          update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary
        )
        .and_call_original
      # "0.1.12" (caret) already allows 0.1.40, so the requirement is left as-is.
      expect(checker.updated_requirements)
        .to eq(
          [{
            file: "Cargo.toml",
            requirement: "0.1.12",
            groups: [],
            source: nil
          }]
        )
    end

    context "with an insecure version" do
      let(:dependency_version) { "0.1.38" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "cargo",
            vulnerable_versions: ["<= 0.1.38"]
          )
        ]
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater)
          .to receive(:new)
          .with(
            requirements: requirements,
            updated_source: nil,
            target_version: "0.1.39",
            update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary
          )
          .and_call_original
        # "0.1.12" already allows the 0.1.39 fix, so only the lockfile changes.
        expect(checker.updated_requirements)
          .to eq(
            [{
              file: "Cargo.toml",
              requirement: "0.1.12",
              groups: [],
              source: nil
            }]
          )
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    it { is_expected.to be(true) }

    context "with the lockfile-only requirements update strategy set" do
      let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }

      it { is_expected.to be(false) }
    end
  end

  describe "#requirements_update_strategy" do
    subject(:strategy) { checker.requirements_update_strategy }

    context "with no explicit strategy and a lockfile present" do
      it "defaults to BumpVersionsIfNecessary" do
        expect(strategy).to eq(Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary)
      end
    end

    context "with no explicit strategy and no lockfile" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: fixture("manifests", manifest_fixture_name)
          )
        ]
      end

      it "defaults to BumpVersionsIfNecessary" do
        expect(strategy).to eq(Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary)
      end
    end

    context "when an explicit strategy is passed" do
      let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }

      it "honours the explicit strategy" do
        expect(strategy).to eq(Dependabot::RequirementsUpdateStrategy::LockfileOnly)
      end
    end
  end

  context "with multiple locked versions of a transitive dependency" do
    let(:manifest_fixture_name) { "multiple_locked_versions" }
    let(:lockfile_fixture_name) { "multiple_locked_versions" }
    let(:crates_response) { "{}" }
    let(:dependency) do
      Dependabot::Cargo::FileParser.new(dependency_files: dependency_files, source: nil)
                                   .parse
                                   .find { |candidate| candidate.name == "getrandom" }
    end

    before do
      latest_version_finder = instance_double(
        Dependabot::Cargo::UpdateChecker::LatestVersionFinder,
        latest_version: Dependabot::Cargo::Version.new("0.4.3"),
        lowest_security_fix_version: Dependabot::Cargo::Version.new("0.4.3")
      )
      allow(Dependabot::Cargo::UpdateChecker::LatestVersionFinder)
        .to receive(:new).and_return(latest_version_finder)
    end

    it "updates the newer compatible line without changing the older line" do
      updated_dependencies = checker.updated_dependencies(requirements_to_unlock: :own)

      expect(updated_dependencies.map { |candidate| [candidate.previous_version, candidate.version] })
        .to eq([["0.4.2", "0.4.3"]])
    end

    context "when every locked line is at its compatible ceiling" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "getrandom",
          version: "0.2.17",
          requirements: [],
          package_manager: "cargo",
          metadata: { all_versions: locked_versions }
        )
      end
      let(:locked_versions) do
        ["0.2.17", "0.4.3"].map do |version|
          Dependabot::Dependency.new(
            name: "getrandom",
            version: version,
            requirements: [],
            package_manager: "cargo",
            metadata: { cargo_package_source: "registry+https://github.com/rust-lang/crates.io-index" }
          )
        end
      end

      before do
        allow(Dependabot::Cargo::UpdateChecker::VersionResolver).to receive(:new) do |dependency:, **|
          instance_double(
            Dependabot::Cargo::UpdateChecker::VersionResolver,
            latest_resolvable_version: Dependabot::Cargo::Version.new(dependency.version)
          )
        end
      end

      it "is up to date when each line resolves to its current version" do
        expect(checker).to be_up_to_date
      end
    end

    context "when more than one locked line is independently updateable" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "getrandom",
          version: "0.2.16",
          requirements: [],
          package_manager: "cargo",
          metadata: { all_versions: locked_versions }
        )
      end
      let(:locked_versions) do
        ["0.2.16", "0.4.2"].map do |version|
          Dependabot::Dependency.new(
            name: "getrandom",
            version: version,
            requirements: [],
            package_manager: "cargo",
            metadata: { cargo_package_source: "registry+https://github.com/rust-lang/crates.io-index" }
          )
        end
      end

      before do
        allow(Dependabot::Cargo::UpdateChecker::VersionResolver).to receive(:new) do |dependency:, **|
          resolved_version = { "0.2.16" => "0.2.17", "0.4.2" => "0.4.3" }.fetch(dependency.version)
          instance_double(
            Dependabot::Cargo::UpdateChecker::VersionResolver,
            latest_resolvable_version: Dependabot::Cargo::Version.new(resolved_version)
          )
        end
      end

      it "returns an update for each exact locked package" do
        updated_dependencies = checker.updated_dependencies(requirements_to_unlock: :own)

        expect(updated_dependencies.map { |candidate| [candidate.previous_version, candidate.version] })
          .to eq([["0.2.16", "0.2.17"], ["0.4.2", "0.4.3"]])
      end

      context "when all updates for one locked line are ignored" do
        let(:raise_on_ignored) { true }

        before do
          allow(Dependabot::Cargo::UpdateChecker::LatestVersionFinder).to receive(:new) do |dependency:, **|
            finder = instance_double(Dependabot::Cargo::UpdateChecker::LatestVersionFinder)
            allow(finder).to receive(:lowest_security_fix_version)
              .and_return(Dependabot::Cargo::Version.new("0.4.3"))
            if dependency.version == "0.4.2"
              allow(finder).to receive(:latest_version).and_raise(Dependabot::AllVersionsIgnored)
            else
              allow(finder).to receive(:latest_version).and_return(Dependabot::Cargo::Version.new("0.2.17"))
            end
            finder
          end
        end

        it "updates the allowed line without leaking the ignored error" do
          updated_dependencies = checker.updated_dependencies(requirements_to_unlock: :own)

          expect(updated_dependencies.map { |candidate| [candidate.previous_version, candidate.version] })
            .to eq([["0.2.16", "0.2.17"]])
        end
      end

      context "when one line is at its ceiling and the other line's updates are all ignored" do
        let(:raise_on_ignored) { true }

        before do
          allow(Dependabot::Cargo::UpdateChecker::LatestVersionFinder).to receive(:new) do |dependency:, **|
            finder = instance_double(Dependabot::Cargo::UpdateChecker::LatestVersionFinder)
            if dependency.version == "0.4.2"
              allow(finder).to receive(:latest_version).and_raise(Dependabot::AllVersionsIgnored)
            else
              allow(finder).to receive(:latest_version).and_return(Dependabot::Cargo::Version.new("0.4.2"))
            end
            finder
          end
          allow(Dependabot::Cargo::UpdateChecker::VersionResolver).to receive(:new) do |dependency:, **|
            instance_double(
              Dependabot::Cargo::UpdateChecker::VersionResolver,
              latest_resolvable_version: Dependabot::Cargo::Version.new(dependency.version)
            )
          end
        end

        it "re-raises instead of reporting the dependency as current" do
          expect { checker.up_to_date? }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end

      context "when all updates for every locked line are ignored" do
        let(:raise_on_ignored) { true }

        before do
          allow(Dependabot::Cargo::UpdateChecker::LatestVersionFinder).to receive(:new) do
            finder = instance_double(Dependabot::Cargo::UpdateChecker::LatestVersionFinder)
            allow(finder).to receive(:latest_version).and_raise(Dependabot::AllVersionsIgnored)
            finder
          end
        end

        it "re-raises so the ignored status is reported" do
          expect { checker.up_to_date? }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end

      context "when performing a security update" do
        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: "getrandom",
              package_manager: "cargo",
              vulnerable_versions: [">= 0.4.0, < 0.4.3"]
            )
          ]
        end

        it "updates only vulnerable locked packages" do
          updated_dependencies = checker.updated_dependencies(requirements_to_unlock: :own)

          expect(updated_dependencies.map { |candidate| [candidate.previous_version, candidate.version] })
            .to eq([["0.4.2", "0.4.3"]])
        end

        context "when the advisory matches every locked line" do
          let(:security_advisories) do
            [
              Dependabot::SecurityAdvisory.new(
                dependency_name: "getrandom",
                package_manager: "cargo",
                vulnerable_versions: [">= 0.2.0, < 0.2.17", ">= 0.4.0, < 0.4.3"]
              )
            ]
          end

          it "returns an update for every vulnerable locked line" do
            updated_dependencies = checker.updated_dependencies(requirements_to_unlock: :own)

            expect(updated_dependencies.map { |candidate| [candidate.previous_version, candidate.version] })
              .to eq([["0.2.16", "0.2.17"], ["0.4.2", "0.4.3"]])
          end
        end
      end
    end
  end

  describe "with cooldown options" do
    let(:update_cooldown) do
      Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
    end
    let(:expected_cooldown_options) do
      Dependabot::Package::ReleaseCooldownOptions.new(
        default_days: 7,
        semver_major_days: 7,
        semver_minor_days: 7,
        semver_patch_days: 7,
        include: [],
        exclude: []
      )
    end

    before do
      latest_version = instance_double(Dependabot::Cargo::UpdateChecker::LatestVersionFinder)
      allow(latest_version)
        .to receive(:latest_version).and_return(Gem::Version.new("1.5.0"))
      allow(Dependabot::Cargo::UpdateChecker::LatestVersionFinder)
        .to receive(:new).and_return(latest_version)
    end

    it "passes cooldown_options to LatestVersionFinder" do
      checker.latest_version

      expect(Dependabot::Cargo::UpdateChecker::LatestVersionFinder).to have_received(:new).with(
        hash_including(
          cooldown_options: an_object_having_attributes(
            default_days: expected_cooldown_options.default_days,
            semver_major_days: expected_cooldown_options.semver_major_days,
            semver_minor_days: expected_cooldown_options.semver_minor_days,
            semver_patch_days: expected_cooldown_options.semver_patch_days,
            include: expected_cooldown_options.include,
            exclude: expected_cooldown_options.exclude
          )
        )
      )
    end
  end

  # Test cases for version capping fix - prevents VersionResolver from returning
  # versions higher than latest_version
  describe "#fetch_latest_resolvable_version version capping" do
    subject(:fetch_latest_resolvable_version) do
      checker.send(:fetch_latest_resolvable_version, unlock_requirement: true)
    end

    # Use time dependency (which has existing fixtures) but override with our test scenario
    let(:dependency_name) { "time" }
    let(:dependency_version) { "0.0.7" }
    let(:manifest_fixture_name) { "bare_version_specified" }
    let(:lockfile_fixture_name) { "bare_version_specified" }

    # Override the requirements to match our test scenario
    let(:requirements) do
      [{ file: "Cargo.toml", requirement: "0.0.7", groups: [], source: nil }]
    end

    context "when VersionResolver returns a version higher than latest_version" do
      before do
        # Create a mock VersionResolver instance
        version_resolver = instance_double(Dependabot::Cargo::UpdateChecker::VersionResolver)
        allow(version_resolver).to receive(:latest_resolvable_version).and_return(Gem::Version.new("0.1.0"))

        # Mock VersionResolver.new to return our mock
        allow(Dependabot::Cargo::UpdateChecker::VersionResolver)
          .to receive(:new)
          .and_return(version_resolver)

        # Mock latest_version to return 0.0.8
        allow(checker).to receive(:latest_version).and_return(Gem::Version.new("0.0.8"))
      end

      it "caps the result to latest_version" do
        expect(fetch_latest_resolvable_version).to eq(Gem::Version.new("0.0.8"))
      end
    end

    context "when VersionResolver returns a version equal to latest_version" do
      before do
        # Create a mock VersionResolver instance
        version_resolver = instance_double(Dependabot::Cargo::UpdateChecker::VersionResolver)
        allow(version_resolver).to receive(:latest_resolvable_version).and_return(Gem::Version.new("0.0.8"))

        # Mock VersionResolver.new to return our mock
        allow(Dependabot::Cargo::UpdateChecker::VersionResolver)
          .to receive(:new)
          .and_return(version_resolver)

        allow(checker).to receive(:latest_version).and_return(Gem::Version.new("0.0.8"))
      end

      it "returns the resolved version unchanged" do
        expect(fetch_latest_resolvable_version).to eq(Gem::Version.new("0.0.8"))
      end
    end

    context "when VersionResolver returns a version lower than latest_version" do
      before do
        # Create a mock VersionResolver instance
        version_resolver = instance_double(Dependabot::Cargo::UpdateChecker::VersionResolver)
        allow(version_resolver).to receive(:latest_resolvable_version).and_return(Gem::Version.new("0.0.7"))

        # Mock VersionResolver.new to return our mock
        allow(Dependabot::Cargo::UpdateChecker::VersionResolver)
          .to receive(:new)
          .and_return(version_resolver)

        allow(checker).to receive(:latest_version).and_return(Gem::Version.new("0.0.8"))
      end

      it "returns the resolved version unchanged" do
        expect(fetch_latest_resolvable_version).to eq(Gem::Version.new("0.0.7"))
      end
    end

    context "with git dependency (should not apply version capping)" do
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:manifest_fixture_name) { "git_dependency" }
      let(:lockfile_fixture_name) { "git_dependency" }
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: nil
          }
        }]
      end

      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .with(basic_auth: %w(x-access-token token))
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      it "does not apply version capping for git dependencies" do
        # Git dependencies should not be subject to version capping
        # since they return SHA hashes, not semantic versions
        expect { fetch_latest_resolvable_version }.not_to raise_error
      end
    end
  end
end
