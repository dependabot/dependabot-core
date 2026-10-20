# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/update_checker"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe(Dependabot::NpmAndYarn::UpdateChecker) do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) { project_dependency_files("yarn_berry/version_scoped_security") }

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "brace-expansion", version: "1.1.18", requirements: [], package_manager: "npm_and_yarn"
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
          dependency_name: "brace-expansion",
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
    stub_request(:get, "https://registry.npmjs.org/brace-expansion").to_return(
      status: 200,
      body: JSON.generate(
        "name" => "brace-expansion",
        "dist-tags" => { "latest" => "5.0.12" },
        "versions" => releases.to_h do |version|
          [version, { "name" => "brace-expansion", "version" => version }]
        end
      )
    )
    stub_request(:head, %r{https://registry.npmjs.org/brace-expansion/-/brace-expansion-.*\.tgz})
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
end
