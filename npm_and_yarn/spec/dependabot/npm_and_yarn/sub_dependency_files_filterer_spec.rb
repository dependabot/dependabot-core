# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/experiments"
require "dependabot/npm_and_yarn/sub_dependency_files_filterer"

RSpec.describe Dependabot::NpmAndYarn::SubDependencyFilesFilterer do
  before do
    Dependabot::Experiments.register(:yarn_berry, true)
  end

  subject(:files_requiring_update) do
    described_class.new(
      dependency_files: dependency_files,
      updated_dependencies: updated_dependencies
    ).files_requiring_update
  end

  let(:dependency_files) do
    project_dependency_files(project_name)
  end
  let(:project_name) { "npm6_and_yarn/nested_sub_dependency_update" }
  let(:updated_dependencies) { [dependency] }

  def project_dependency_file(file_name)
    dependency_files.find { |f| f.name == file_name }
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "extend",
      version: "2.0.2",
      previous_version: nil,
      requirements: [],
      package_manager: "npm_and_yarn"
    )
  end

  describe ".files_requiring_update" do
    it do
      is_expected.to contain_exactly(
        project_dependency_file("packages/package1/package-lock.json"),
        project_dependency_file("packages/package3/yarn.lock")
      )
    end

    context "when the version is out of range" do
      let(:project_name) { "npm6_and_yarn/nested_sub_dependency_update_npm_out_of_range" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "extend",
          version: "1.3.0",
          previous_version: nil,
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it do
        is_expected.to contain_exactly(
          project_dependency_file("packages/package4/package-lock.json")
        )
      end
    end
  end
end
