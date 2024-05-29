# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/file_parser"
require "dependabot/nuget/update_checker/tfm_finder"

RSpec.describe Dependabot::Nuget::TfmFinder do
  subject(:frameworks) do
    Dependabot::Nuget::FileParser.new(dependency_files: dependency_files,
                                      source: source,
                                      repo_contents_path: repo_contents_path).parse
    Dependabot::Nuget::TfmFinder.frameworks(dependency)
  end

  let(:project_name) { "tfm_finder" }
  let(:dependency_files) { nuget_project_dependency_files(project_name, directory: "/").reverse }
  let(:repo_contents_path) { nuget_build_tmp_repo(project_name) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "nuget"
    )
  end

  describe "#frameworks" do
    context "when checking for a transitive dependency" do
      let(:dependency_requirements) { [] }
      let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
      let(:dependency_version) { "1.1.1" }

      its(:length) { is_expected.to eq(2) }
    end

    context "when checking for a top-level dependency" do
      let(:dependency_requirements) do
        [{ file: "my.csproj", requirement: "2.3.0", groups: ["dependencies"], source: nil }]
      end
      let(:dependency_name) { "Serilog" }
      let(:dependency_version) { "2.3.0" }

      its(:length) { is_expected.to eq(1) }
    end
  end
end
