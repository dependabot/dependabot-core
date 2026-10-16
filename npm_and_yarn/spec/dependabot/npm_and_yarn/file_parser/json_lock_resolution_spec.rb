# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_parser/json_lock"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet
RSpec.describe Dependabot::NpmAndYarn::FileParser::JsonLock do
  extend T::Sig

  sig { returns(Dependabot::DependencyFile) }
  let(:original) do
    files = project_dependency_files("npm8/multiple_brace_expansion_versions")
    lockfile = T.must(files.find { |file| file.name == "package-lock.json" })
    content = JSON.parse(T.must(lockfile.content))
    content.fetch("packages")["node_modules/another-parent/node_modules/brace-expansion"] = { "version" => "2.1.2" }
    lockfile.dup.tap { |copy| copy.content = JSON.generate(content) }
  end

  sig { returns(Dependabot::DependencyFile) }
  let(:updated) do
    original.dup.tap { |copy| copy.content = T.must(original.content).gsub('"2.1.2"', '"2.1.4"') }
  end

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "npm_and_yarn"
    )
  end

  it "detects each lockfile format once, independently of record and target counts" do
    allow(Dependabot::NpmAndYarn::Helpers).to receive(:parse_npm8?).and_call_original

    version = described_class.new(updated).updated_dependency_version(dependency: dependency, original: original)

    expect(version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
    expect(Dependabot::NpmAndYarn::Helpers).to have_received(:parse_npm8?).with(original).once
    expect(Dependabot::NpmAndYarn::Helpers).to have_received(:parse_npm8?).with(updated).once
  end
end
