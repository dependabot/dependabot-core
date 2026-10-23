# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/npm_and_yarn/update_checker/dependency_files_builder"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::DependencyFilesBuilder do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let!(:dependency_files) { project_dependency_files("yarn/multiple_brace_expansion_versions") }

  sig { returns(Dependabot::NpmAndYarn::UpdateChecker::DependencyFilesBuilder) }
  let(:builder) do
    described_class.new(
      dependency: Dependabot::Dependency.new(
        name: "brace-expansion",
        version: "2.1.2",
        requirements: [],
        package_manager: "npm_and_yarn"
      ),
      dependency_files: dependency_files,
      credentials: []
    )
  end

  it "still prunes unquoted dependency entries by default for update resolution" do
    Dependabot::SharedHelpers.in_a_temporary_directory do
      builder.write_temporary_dependency_files

      expect(File.read("yarn.lock")).not_to include("brace-expansion@")
      expect(File.read("yarn.lock")).to include("current-parent@1.0.0:")
    end
  end

  it "preserves the original lockfile when installed-version evidence is needed" do
    Dependabot::SharedHelpers.in_a_temporary_directory do
      builder.write_temporary_dependency_files(preserve_yarn_lockfile_entries: true)

      expect(File.read("yarn.lock")).to eq(dependency_files.find { |file| file.name == "yarn.lock" }&.content)
    end
  end
end
