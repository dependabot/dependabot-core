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
      security_advisories: [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "npm_and_yarn",
          vulnerable_versions: ["< 1.1.21", ">= 2.0.0 < 2.1.7", ">= 5.0.0 < 5.0.12"].flat_map do |requirement|
            Dependabot::NpmAndYarn::Requirement.requirements_array(requirement)
          end
        )
      ]
    )
  end

  before do
    releases = %w(1.1.18 1.1.21 2.1.7 5.0.12)
    stub_request(:get, "https://registry.npmjs.org/#{dependency_name.gsub('/', '%2F')}").to_return(
      status: 200,
      body: JSON.generate(
        "name" => dependency_name,
        "dist-tags" => { "latest" => "5.0.12", "maintenance" => "1.1.21" },
        "versions" => releases.to_h do |version|
          [version, { "name" => dependency_name, "version" => version }]
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

  context "when the vulnerable installation is pinned" do
    sig { returns(String) }
    let(:installed_requirement) { "1.1.18" }

    it "retains a secure target for reporting the blocking parent" do
      expect(checker.up_to_date?).to be(false)
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
      expect(checker.conflicting_dependencies.map { |conflict| conflict.fetch("requirement") }).to eq(["1.1.18"])
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
end
