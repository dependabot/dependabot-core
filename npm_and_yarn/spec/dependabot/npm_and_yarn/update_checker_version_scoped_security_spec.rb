# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/update_checker"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe(Dependabot::NpmAndYarn::UpdateChecker) do
  extend T::Sig

  sig { returns(String) }
  let(:dependency_name) { "brace-expansion" }

  sig { returns(String) }
  let(:installed_requirement) { "^1.1.17" }

  sig { returns(T::Array[String]) }
  let(:ignored_versions) { [] }

  sig { returns(T::Hash[String, T::Boolean]) }
  let(:in_range_release_details) { {} }

  sig { returns(T::Array[String]) }
  let(:releases) { %w(1.1.18 1.1.21 2.1.7 5.0.12) }

  sig { returns(T::Hash[String, String]) }
  let(:dist_tags) { { "latest" => "5.0.12", "maintenance" => "1.1.21", "_maintenance" => "1.1.21" } }

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) do
    project_dependency_files("yarn_berry/version_scoped_security").map do |file|
      content = T.must(file.content).gsub("brace-expansion", dependency_name)
                 .gsub("^1.1.17", installed_requirement)
                 .gsub("    #{dependency_name}:", "    #{JSON.generate(dependency_name)}:")
      Dependabot::DependencyFile.new(name: file.name, content: content, directory: file.directory)
    end
  end

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name, version: "1.1.18", requirements: [], package_manager: "npm_and_yarn"
    )
  end

  sig { returns(Dependabot::NpmAndYarn::UpdateChecker) }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: ignored_versions,
      raise_on_ignored: true,
      security_advisories: [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "npm_and_yarn",
          vulnerable_versions: ["< 1.1.21", ">= 1.2.0 < 2.1.7", ">= 5.0.0 < 5.0.12"].flat_map do |requirement|
            Dependabot::NpmAndYarn::Requirement.requirements_array(requirement)
          end
        )
      ]
    )
  end

  before do
    stub_request(:get, "https://registry.npmjs.org/#{dependency_name.gsub('/', '%2F')}").to_return(
      status: 200,
      body: JSON.generate(
        "name" => dependency_name,
        "dist-tags" => dist_tags,
        "versions" => releases.to_h do |version|
          details = { "name" => dependency_name, "version" => version }
          [version, version == "1.1.21" ? details.merge(in_range_release_details) : details]
        end
      )
    )
    stub_request(:head, %r{\Ahttps://registry\.npmjs\.org/#{Regexp.escape(dependency_name)}/-/[^/]+\.tgz\z})
      .to_return(status: 200)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_audit_fix_fallback).and_return(false)
  end

  it "selects the latest release in the range resolving to the vulnerable installation" do
    expect(checker.latest_version.to_s).to eq("1.1.21")
  end

  it "does not treat other installed versions' ranges as conflicts" do
    expect(checker.conflicting_dependencies).to be_empty
  end

  it "finds the in-range security fix" do
    expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
  end

  it "allows the in-range security update to resolve" do
    allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command) do
      lockfile = YAML.safe_load_file("yarn.lock")
      record = lockfile.fetch("brace-expansion@npm:^1.1.17")
      record["version"] = "1.1.21"
      record["resolution"] = "brace-expansion@npm:1.1.21"
      File.write("yarn.lock", YAML.dump(lockfile))
      ""
    end

    expect(checker.lowest_resolvable_security_fix_version.to_s).to eq("1.1.21")
  end

  it "retains conflicts from requirements resolving to the targeted installation" do
    conflicts = Dependabot::NpmAndYarn::UpdateChecker::ConflictingDependencyResolver.new(
      dependency_files: dependency_files, credentials: []
    ).conflicting_dependencies(dependency: dependency, target_version: "2.1.7")

    expect(conflicts.map { |conflict| conflict.fetch("requirement") }).to eq(["^1.1.17"])
  end

  context "when a higher in-range release is vulnerable" do
    sig { returns(T::Array[String]) }
    let(:releases) { %w(1.1.18 1.1.21 1.2.0 2.1.7 5.0.12) }

    it "selects and resolves the secure backport instead" do
      allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command) do
        lockfile = YAML.safe_load_file("yarn.lock")
        record = lockfile.fetch("brace-expansion@npm:^1.1.17")
        record["version"] = "1.1.21"
        record["resolution"] = "brace-expansion@npm:1.1.21"
        File.write("yarn.lock", YAML.dump(lockfile))
        ""
      end

      expect(checker.latest_version.to_s).to eq("1.1.21")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
      expect(checker.lowest_resolvable_security_fix_version.to_s).to eq("1.1.21")
    end
  end

  context "when the vulnerable installation is pinned" do
    sig { returns(String) }
    let(:installed_requirement) { "1.1.18" }

    it "retains a secure target for reporting the blocking parent" do
      expect(checker.up_to_date?).to be(false)
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
      expect(checker.conflicting_dependencies.map { |conflict| conflict.fetch("requirement") }).to eq(["1.1.18"])
    end
  end

  context "when the only in-range security fix is deprecated" do
    sig { returns(T::Hash[String, T::Boolean]) }
    let(:in_range_release_details) { { "deprecated" => true } }

    it "retains an eligible security target for blocker diagnostics" do
      expect(checker.up_to_date?).to be(false)
      expect(checker.lowest_security_fix_version.to_s).to eq("2.1.7")
      expect(checker.conflicting_dependencies.map { |conflict| conflict.fetch("requirement") }).to eq(["^1.1.17"])
    end
  end

  context "when the only in-range security fix is ignored" do
    sig { returns(T::Array[String]) }
    let(:ignored_versions) { ["1.1.21"] }

    it "retains an eligible security target for blocker diagnostics" do
      expect(checker.up_to_date?).to be(false)
      expect(checker.lowest_security_fix_version.to_s).to eq("2.1.7")
      expect(checker.conflicting_dependencies.map { |conflict| conflict.fetch("requirement") }).to eq(["^1.1.17"])
    end
  end

  context "when the only in-range security fix is yanked" do
    before do
      stub_request(:head, "https://registry.npmjs.org/brace-expansion/-/brace-expansion-1.1.21.tgz")
        .to_return(status: 404)
    end

    it "retains an eligible security target for blocker diagnostics" do
      expect(checker.up_to_date?).to be(false)
      expect(checker.lowest_security_fix_version.to_s).to eq("2.1.7")
      expect(checker.conflicting_dependencies.map { |conflict| conflict.fetch("requirement") }).to eq(["^1.1.17"])
    end
  end

  context "when all security fixes are ignored" do
    sig { returns(T::Array[String]) }
    let(:ignored_versions) { %w(1.1.21 2.1.7 5.0.12) }

    it "raises after filtering all security fix candidates" do
      expect { checker.lowest_security_fix_version }.to raise_error(Dependabot::AllVersionsIgnored)
    end
  end

  context "when the vulnerable installation is only referenced through an npm alias" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      T.cast(super(), T::Array[Dependabot::DependencyFile]).map do |file|
        next file unless file.name == "yarn.lock"

        content = T.must(file.content)
                   .sub("\"#{dependency_name}@npm:^1.1.17\"",
                        "\"legacy-brace@npm:#{dependency_name}@^1.1.17\"")
                   .sub("#{JSON.generate(dependency_name)}: \"npm:^1.1.17\"",
                        "legacy-brace: \"npm:#{dependency_name}@^1.1.17\"")
        Dependabot::DependencyFile.new(name: file.name, content: content, directory: file.directory)
      end
    end

    it "selects the in-range security update" do
      expect(checker.latest_version.to_s).to eq("1.1.21")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
      expect(checker.conflicting_dependencies).to be_empty
    end

    context "with a scoped real package name" do
      sig { returns(String) }
      let(:dependency_name) { "@scope/brace-expansion" }

      it "selects the in-range security update" do
        expect(checker.latest_version.to_s).to eq("1.1.21")
        expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
        expect(checker.conflicting_dependencies).to be_empty
      end
    end
  end

  context "when the lockfile descriptor uses a standard dist-tag" do
    sig { returns(String) }
    let(:installed_requirement) { "latest" }

    it "does not filter numeric security fixes using the tag as a semver range" do
      expect(checker.latest_version.to_s).to eq("5.0.12")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
    end
  end

  context "when the lockfile descriptor uses a custom dist-tag" do
    sig { returns(String) }
    let(:installed_requirement) { "maintenance" }

    it "does not raise or discard numeric security fixes" do
      expect(checker.latest_version.to_s).to eq("5.0.12")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
    end
  end

  context "when the lockfile descriptor uses an underscore-prefixed dist-tag" do
    sig { returns(String) }
    let(:installed_requirement) { "_maintenance" }

    it "recognizes the registry tag without parsing it as a semver range" do
      expect(checker.latest_version.to_s).to eq("5.0.12")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
    end

    context "when the tag has been removed from the registry" do
      sig { returns(T::Hash[String, String]) }
      let(:dist_tags) { { "latest" => "5.0.12" } }

      it "skips the unparseable selector and retains numeric security fixes" do
        expect(checker.latest_version.to_s).to eq("5.0.12")
        expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
      end
    end
  end
end
