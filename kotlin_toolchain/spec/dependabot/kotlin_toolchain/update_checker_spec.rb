# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/security_advisory"
require "dependabot/kotlin_toolchain/requirement"
require "dependabot/kotlin_toolchain/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::KotlinToolchain::UpdateChecker do
  subject(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: [],
      ignored_versions: [],
      security_advisories: []
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "io.ktor:ktor-server-core",
      version: "3.1.0",
      requirements: [{
        file: "module.yaml",
        requirement: "3.1.0",
        groups: ["dependencies"],
        source: nil,
        metadata: {
          kind: "yaml_value",
          path: ["dependencies", 0],
          value: "io.ktor:ktor-server-core:3.1.0"
        }
      }],
      package_manager: "kotlin_toolchain"
    )
  end
  let(:version_finder) { instance_double(described_class::VersionFinder) }

  before do
    allow(described_class::VersionFinder).to receive(:new).and_return(version_finder)
    allow(version_finder).to receive_messages(
      latest_version_details: {
        version: Dependabot::KotlinToolchain::Version.new("3.2.0"),
        source_url: "https://repo.maven.apache.org/maven2"
      },
      lowest_security_fix_version_details: nil
    )
  end

  it_behaves_like "an update checker"

  it "returns the latest Maven version" do
    expect(checker.latest_version).to eq(Dependabot::KotlinToolchain::Version.new("3.2.0"))
  end

  it "updates requirements while preserving source-location metadata" do
    requirement = checker.updated_requirements.first

    expect(requirement[:requirement]).to eq("3.2.0")
    expect(requirement[:metadata]).to eq(dependency.requirements.first[:metadata])
  end

  it "offers nothing without unlocking the requirement" do
    expect(checker.latest_resolvable_version_with_no_unlock).to be_nil
  end

  it "has nothing to unlock for a declaration that shares no version key" do
    expect(checker.send(:latest_version_resolvable_with_full_unlock?)).to be(false)
  end

  it "accepts a plain string version from the finder" do
    allow(version_finder).to receive(:latest_version_details).and_return({ version: "3.3.0" })

    expect(checker.latest_version).to eq(Dependabot::KotlinToolchain::Version.new("3.3.0"))
  end

  it "leaves the requirements alone when the finder returns nothing" do
    allow(version_finder).to receive(:latest_version_details).and_return(nil)

    expect(checker.latest_version).to be_nil
    expect(checker.updated_requirements.first[:requirement]).to eq("3.1.0")
  end

  context "when the same coordinate is pinned higher in another file" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "org.example:lib",
        version: "1.0.0",
        requirements: [
          {
            file: "module.yaml",
            requirement: "1.0.0",
            groups: ["dependencies"],
            source: nil,
            metadata: { kind: "yaml_value", path: ["dependencies", 0], value: "org.example:lib:1.0.0" }
          },
          {
            file: "libs.versions.toml",
            requirement: "2.0.0",
            groups: ["dependencies"],
            source: nil,
            metadata: { kind: "catalog_inline", alias: "lib", value: "2.0.0" }
          }
        ],
        package_manager: "kotlin_toolchain"
      )
    end

    before do
      allow(version_finder).to receive(:latest_version_details).and_return(
        version: Dependabot::KotlinToolchain::Version.new("1.5.0"),
        source_url: "https://repo.maven.apache.org/maven2"
      )
    end

    it "bumps only the file that is below the target" do
      expect(checker.updated_requirements.map { |req| req[:requirement] }).to eq(%w(1.5.0 2.0.0))
    end
  end

  context "with a version key shared by two catalog libraries" do
    subject(:checker) do
      described_class.new(
        dependency: dependency,
        dependency_files: [catalog],
        credentials: [],
        ignored_versions: [],
        security_advisories: []
      )
    end

    let(:catalog) do
      Dependabot::DependencyFile.new(
        name: "libs.versions.toml",
        content: <<~TOML
          [versions]
          kotlin = "2.0.0"

          [libraries]
          stdlib = { module = "org.jetbrains.kotlin:kotlin-stdlib", version.ref = "kotlin" }
          reflect = { module = "org.jetbrains.kotlin:kotlin-reflect", version.ref = "kotlin" }
        TOML
      )
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "org.jetbrains.kotlin:kotlin-stdlib",
        version: "2.0.0",
        requirements: [{
          file: "libs.versions.toml",
          requirement: "2.0.0",
          groups: ["dependencies"],
          source: nil,
          metadata: { kind: "catalog_version", alias: "stdlib", version_key: "kotlin", value: "2.0.0", profile: "0.12" }
        }],
        package_manager: "kotlin_toolchain"
      )
    end
    let(:sibling_versions) { [{ version: Dependabot::KotlinToolchain::Version.new("3.2.0") }] }

    before do
      allow(version_finder).to receive(:versions).and_return(sibling_versions)
    end

    it "refuses to move the key for one library alone" do
      expect(checker.latest_version).to eq(Dependabot::KotlinToolchain::Version.new("3.2.0"))
      expect(checker.latest_resolvable_version).to be_nil
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
    end

    it "updates every library on the key together" do
      expect(checker.can_update?(requirements_to_unlock: :all)).to be(true)

      updated = checker.updated_dependencies(requirements_to_unlock: :all)
      expect(updated.map(&:name)).to contain_exactly(
        "org.jetbrains.kotlin:kotlin-stdlib",
        "org.jetbrains.kotlin:kotlin-reflect"
      )
      expect(updated.map(&:version).uniq).to eq(["3.2.0"])
      expect(updated.map(&:previous_version).uniq).to eq(["2.0.0"])
      expect(updated.flat_map(&:requirements).map { |req| req[:requirement] }.uniq).to eq(["3.2.0"])
    end

    context "when the other library is not published at the target version" do
      let(:sibling_versions) { [{ version: Dependabot::KotlinToolchain::Version.new("2.0.0") }] }

      it "does not update at all" do
        expect(checker.can_update?(requirements_to_unlock: :all)).to be(false)
        expect(checker.updated_dependencies(requirements_to_unlock: :all)).to be_empty
      end
    end
  end

  context "with a repository source on the requirement" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "org.jetbrains.kotlin:kotlin-cli",
        version: "0.11.1",
        requirements: [{
          file: "kotlin",
          requirement: "0.11.1",
          groups: ["toolchain"],
          source: { type: "maven_repo", url: "https://packages.jetbrains.team/maven/p/amper/amper" },
          metadata: { kind: "wrapper" }
        }],
        package_manager: "kotlin_toolchain",
        metadata: { wrapper: true }
      )
    end

    it "points the source at the repository that served the version" do
      expect(checker.updated_requirements.first[:source])
        .to eq(type: "maven_repo", url: "https://repo.maven.apache.org/maven2")
    end
  end

  context "when the dependency is vulnerable" do
    subject(:checker) do
      described_class.new(
        dependency: dependency,
        dependency_files: [],
        credentials: [],
        ignored_versions: [],
        security_advisories: [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "io.ktor:ktor-server-core",
            package_manager: "kotlin_toolchain",
            vulnerable_versions: ["< 3.1.5"]
          )
        ]
      )
    end

    before do
      allow(version_finder).to receive(:lowest_security_fix_version_details).and_return(
        version: Dependabot::KotlinToolchain::Version.new("3.1.5"),
        source_url: "https://repo.example.test/maven"
      )
    end

    it "reports the lowest fixed version" do
      expect(checker.lowest_security_fix_version).to eq(Dependabot::KotlinToolchain::Version.new("3.1.5"))
      expect(checker.lowest_resolvable_security_fix_version)
        .to eq(Dependabot::KotlinToolchain::Version.new("3.1.5"))
    end

    it "updates the requirement to the fix instead of the latest version" do
      expect(checker.updated_requirements.first[:requirement]).to eq("3.1.5")
    end
  end
end
