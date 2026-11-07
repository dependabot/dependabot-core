# typed: strict
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/security_advisory"

require "dependabot/vcpkg/package/versions_database"
require "dependabot/vcpkg/update_checker/security_fix_resolver"

RSpec.describe Dependabot::Vcpkg::UpdateChecker::SecurityFixResolver do
  extend T::Sig

  sig { returns(T.nilable(Dependabot::Vcpkg::UpdateChecker::SecurityFixResolver::Fix)) }
  subject(:fix) { resolver.fix }

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Vcpkg::UpdateChecker::SecurityFixResolver) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      lowest_comparable_version: lowest_comparable_version,
      versions_database: versions_database
    )
  end

  sig { returns(Dependabot::Vcpkg::Package::VersionsDatabase) }
  let(:versions_database) { instance_double(Dependabot::Vcpkg::Package::VersionsDatabase) }
  sig { returns(String) }
  let(:baseline_sha) { "fe1cde61e971d53c9687cf9a46308f8f55da19fa" }
  sig { returns(String) }
  let(:port) { "zlib" }
  sig { returns(T.nilable(String)) }
  let(:current_version) { "1.2.11" }
  sig { returns(T.nilable(Integer)) }
  let(:constraint) { nil }
  sig { returns(T::Array[String]) }
  let(:ignored_versions) { [] }
  sig { returns(T.nilable(Dependabot::Vcpkg::Version)) }
  let(:lowest_comparable_version) { nil }

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "vcpkg.json",
        content: %({ "builtin-baseline": "#{baseline_sha}", "dependencies": ["#{port}"] })
      )
    ]
  end

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: port,
      version: current_version,
      package_manager: "vcpkg",
      requirements: [{ requirement: constraint, groups: [], source: nil, file: "vcpkg.json" }]
    )
  end

  sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
  let(:security_advisories) do
    [
      Dependabot::SecurityAdvisory.new(
        dependency_name: port,
        package_manager: "vcpkg",
        vulnerable_versions: Dependabot::Vcpkg::Requirement.requirements_array("<= 1.2.12")
      )
    ]
  end

  # Release tags oldest first, with the version floor each one sets for the port.
  sig { returns(T::Hash[String, String]) }
  let(:tag_baselines) do
    {
      "2021.04.30" => "1.2.11",
      "2021.05.12" => "1.2.11#10",
      "2022.01.01" => "1.2.12",
      "2023.01.09" => "1.2.13",
      "2024.01.12" => "1.3.1"
    }
  end

  sig { returns(T::Array[String]) }
  let(:published_versions) { %w(1.3.1 1.2.13 1.2.12 1.2.11#10 1.2.11) }
  # rubocop:enable RSpec/ScatteredLet

  before do
    allow(versions_database).to receive_messages(
      release_tags: tag_baselines.keys,
      commit_sha_for: "c" * 40
    )
    allow(versions_database).to receive(:ancestor?) do |ancestor:, descendant:|
      ancestor == baseline_sha && tag_baselines.keys.index(descendant).to_i >= 1
    end
    allow(versions_database).to receive(:baseline_version_for) do |port:, ref:|
      _ = port
      text = tag_baselines[ref]
      text && Dependabot::Vcpkg::Version.new(text)
    end
    allow(versions_database).to receive(:versions_for) do
      published_versions.map do |text|
        Dependabot::Vcpkg::Package::VersionsDatabase::PortVersion.new(
          version: Dependabot::Vcpkg::Version.new(text),
          scheme: "version",
          git_tree: text
        )
      end
    end
  end

  describe "raising the baseline" do
    it "picks the oldest release tag whose floor is safe" do
      expect(fix).to have_attributes(
        kind: :baseline,
        version: Dependabot::Vcpkg::Version.new("1.2.13"),
        baseline_tag: "2023.01.09",
        baseline_commit_sha: "c" * 40
      )
    end

    it "never moves the baseline backwards" do
      resolver.fix

      expect(versions_database).not_to have_received(:baseline_version_for).with(port:, ref: "2021.04.30")
    end

    it "resolves the advisory even when a constraint is declared below the new floor" do
      T.must(dependency.requirements.first)[:requirement] = ">=1.2.11"

      expect(T.must(fix).kind).to eq(:baseline)
    end

    context "with a malformed declared constraint" do
      sig { returns(Integer) }
      let(:constraint) { 1 }

      it "raises a type error" do
        expect { fix }
          .to raise_error(TypeError, "requirement must be a string, :unfixable, or nil")
      end
    end

    context "when the release floors are all still vulnerable" do
      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: Dependabot::Vcpkg::Requirement.requirements_array("<= 1.3.1")
          )
        ]
      end

      it "offers no fix when nothing else is safe either" do
        expect(fix).to be_nil
      end
    end

    # Advisories enumerate affected versions rather than describing ranges, so a safe floor can sit
    # between two vulnerable ones. Bisecting the tag list would step over it.
    context "when safe floors are not contiguous" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(T::Hash[String, String]) }
      let(:tag_baselines) do
        {
          "2021.04.30" => "7.50.0",
          "2021.05.12" => "7.79.0",
          "2022.01.01" => "7.80.0",
          "2023.01.09" => "7.81.0",
          "2024.01.12" => "7.84.0"
        }
      end
      sig { returns(String) }
      let(:current_version) { "7.10.0" }
      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: Dependabot::Vcpkg::Requirement.requirements_array("< 7.79.0")
          ),
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: Dependabot::Vcpkg::Requirement.requirements_array(">= 7.80.0, < 7.84.0")
          )
        ]
      end
      # rubocop:enable RSpec/ScatteredLet

      it "picks the earliest safe floor rather than skipping past it" do
        expect(fix).to have_attributes(kind: :baseline, baseline_tag: "2021.05.12")
      end
    end

    context "when only the earliest candidate floor is safe" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(T::Hash[String, String]) }
      let(:tag_baselines) do
        {
          "2021.04.30" => "1.9.0",
          "2021.05.12" => "2.0.0",
          "2022.01.01" => "2.1.0",
          "2023.01.09" => "2.2.0"
        }
      end
      sig { returns(String) }
      let(:current_version) { "1.5.0" }
      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: Dependabot::Vcpkg::Requirement.requirements_array("< 2.0.0")
          ),
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: Dependabot::Vcpkg::Requirement.requirements_array(">= 2.1.0")
          )
        ]
      end
      # rubocop:enable RSpec/ScatteredLet

      it "still finds it" do
        expect(fix).to have_attributes(kind: :baseline, baseline_tag: "2021.05.12")
      end
    end

    context "when the manifest pins no baseline" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "vcpkg.json", content: %({ "dependencies": ["zlib"] }))]
      end

      it "falls through to pinning, because there is no baseline to raise" do
        expect(fix).to have_attributes(kind: :override, baseline_tag: nil)
      end
    end
  end

  describe "raising the version constraint" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: port,
          package_manager: "vcpkg",
          vulnerable_versions: Dependabot::Vcpkg::Requirement.requirements_array("<= 1.3.1")
        )
      ]
    end
    sig { returns(T::Array[String]) }
    let(:published_versions) { %w(1.3.2 1.3.1 1.2.13 1.2.12 1.2.11#10 1.2.11) }
    sig { returns(Dependabot::Vcpkg::Version) }
    let(:lowest_comparable_version) { Dependabot::Vcpkg::Version.new("1.3.2") }
    # rubocop:enable RSpec/ScatteredLet

    it "falls back to the constraint when no release floor carries the fix" do
      expect(fix).to have_attributes(
        kind: :version_constraint,
        version: Dependabot::Vcpkg::Version.new("1.3.2"),
        baseline_tag: nil
      )
    end
  end

  describe "pinning with an override" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: port,
          package_manager: "vcpkg",
          vulnerable_versions: Dependabot::Vcpkg::Requirement.requirements_array("<= 1.3.1")
        )
      ]
    end
    sig { returns(T::Array[String]) }
    let(:published_versions) { %w(1.3.2 1.3.1 1.2.13 1.2.12 1.2.11#10 1.2.11) }
    # rubocop:enable RSpec/ScatteredLet

    it "pins the earliest safe version published after the current one" do
      expect(fix).to have_attributes(
        kind: :override,
        version: Dependabot::Vcpkg::Version.new("1.3.2")
      )
    end

    context "when several safe versions were published after the current one" do
      sig { returns(T::Array[String]) }
      let(:published_versions) { %w(1.4.0 1.3.2 1.3.1 1.2.13 1.2.12 1.2.11#10 1.2.11) }

      it "chooses the smallest upgrade" do
        expect(T.must(fix).version).to eq(Dependabot::Vcpkg::Version.new("1.3.2"))
      end
    end

    context "when the only safe versions were published before the current one" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(String) }
      let(:current_version) { "1.3.1" }
      sig { returns(T::Array[String]) }
      let(:published_versions) { %w(1.3.1 1.2.13 1.2.12) }
      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: ["= 1.3.1", "= 1.2.13"].map { |value| Dependabot::Vcpkg::Requirement.new(value) }
          )
        ]
      end
      # rubocop:enable RSpec/ScatteredLet

      it "offers no fix" do
        expect(fix).to be_nil
      end
    end

    context "when the current version is absent from the versions database" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(String) }
      let(:current_version) { "1.3.5" }
      sig { returns(T::Array[String]) }
      let(:published_versions) { %w(1.4.0 1.3.1 1.2.13 1.0.0) }
      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: port,
            package_manager: "vcpkg",
            vulnerable_versions: ["= 1.3.5", ">= 1.4.0"].map { |value| Dependabot::Vcpkg::Requirement.new(value) }
          )
        ]
      end
      # rubocop:enable RSpec/ScatteredLet

      it "offers no pin, rather than downgrading the port" do
        expect(fix).to be_nil
      end
    end
  end

  describe "ignore conditions" do
    sig { returns(T::Array[String]) }
    let(:ignored_versions) { ["> 1.2.11#10"] }

    it "does not offer an ignored version" do
      expect(fix).to be_nil
    end
  end

  describe "when the dependency is not vulnerable data" do
    context "with no advisories" do
      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      let(:security_advisories) { [] }

      it { expect(fix).to be_nil }
    end

    context "with an unparseable current version" do
      sig { returns(NilClass) }
      let(:current_version) { nil }

      it { expect(fix).to be_nil }
    end
  end
end
