# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker/tfm_finder"

RSpec.describe Dependabot::Nuget::TfmFinder do
  subject(:finder) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: credentials,
      repo_contents_path: "test/repo"
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

  let(:dependency_files) { [exe_proj, lib_proj] }
  let(:exe_proj) do
    Dependabot::DependencyFile.new(
      name: "my.csproj",
      content: fixture("csproj", "transitive_project_reference.csproj")
    )
  end
  let(:lib_proj) do
    Dependabot::DependencyFile.new(
      name: "ref/another.csproj",
      content: fixture("csproj", "transitive_referenced_project.csproj")
    )
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before do
    allow(finder).to receive(:project_file_contains_dependency?).with(exe_proj, any_args).and_return(true)
  end

  describe "#frameworks" do
    context "when checking for a transitive dependency" do
      let(:dependency_requirements) { [] }
      let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
      let(:dependency_version) { "1.1.1" }

      subject(:frameworks) { finder.frameworks(dependency) }

      before do
        allow(finder).to receive(:project_file_contains_dependency?).with(lib_proj, dependency).and_return(true)
      end

      its(:length) { is_expected.to eq(2) }
    end

    context "when checking for a top-level dependency" do
      let(:dependency_requirements) do
        [{ file: "my.csproj", requirement: "2.3.0", groups: ["dependencies"], source: nil }]
      end
      let(:dependency_name) { "Serilog" }
      let(:dependency_version) { "2.3.0" }

      subject(:frameworks) { finder.frameworks(dependency) }

      before do
        allow(finder).to receive(:project_file_contains_dependency?).with(lib_proj, dependency).and_return(false)
      end

      its(:length) { is_expected.to eq(1) }
    end
  end
end
