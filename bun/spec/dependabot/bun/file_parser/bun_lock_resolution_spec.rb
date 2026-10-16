# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/file_parser/bun_lock"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet
RSpec.describe Dependabot::Bun::FileParser::BunLock do
  extend T::Sig

  sig { returns(Dependabot::DependencyFile) }
  let(:original) do
    files = project_dependency_files("bun/multiple_brace_expansion_versions")
    lockfile = T.must(files.find { |file| file.name == "bun.lock" })
    content = JSON.parse(T.must(lockfile.content))
    packages = content.fetch("packages")
    20.times do |index|
      name = index.even? ? "@scope/alias-#{index}" : "brace-expansion"
      packages["parent-#{index}"] = [
        "parent-#{index}@1.0.0", "", { "dependencies" => { name => "npm:brace-expansion@^2.0.2" } }, ""
      ]
      packages["parent-#{index}/#{name}"] = ["brace-expansion@2.1.2", "", {}, ""]
    end
    lockfile.dup.tap { |copy| copy.content = JSON.generate(content) }
  end

  sig { returns(Dependabot::DependencyFile) }
  let(:updated) do
    original.dup.tap do |copy|
      copy.content = T.must(original.content).gsub("brace-expansion@2.1.2", "brace-expansion@2.1.4")
    end
  end

  it "scans each original tuple's dependency metadata once across many aliased and regular targets" do
    dependency = Dependabot::Dependency.new(
      name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "bun"
    )
    original_reader = described_class.new(original)
    updated_reader = described_class.new(updated)
    records = T.must(original_reader.records)
    allow(described_class).to receive(:new).with(original).and_return(original_reader)
    records.each_value { |record| allow(record).to receive(:dependency_names).and_call_original }

    version = updated_reader.updated_dependency_version(dependency: dependency, original: original)

    expect(version).to eq(Dependabot::Bun::Version.new("2.1.4"))
    records.each_value { |record| expect(record).to have_received(:dependency_names).once }
  end

  context "without incoming dependency edges" do
    sig { returns(Dependabot::DependencyFile) }
    let(:original) do
      lockfile = T.let(super(), Dependabot::DependencyFile)
      content = JSON.parse(T.must(lockfile.content))
      content.fetch("packages").each_value { |tuple| tuple[2] = {} }
      lockfile.dup.tap { |copy| copy.content = JSON.generate(content) }
    end

    it "preserves path-based verification for regular and scoped alias installations" do
      dependency = Dependabot::Dependency.new(
        name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "bun"
      )

      version = described_class.new(updated).updated_dependency_version(dependency: dependency, original: original)

      expect(version).to eq(Dependabot::Bun::Version.new("2.1.4"))
    end
  end
end
