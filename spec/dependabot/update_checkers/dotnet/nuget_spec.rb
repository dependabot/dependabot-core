# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/dotnet/nuget"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Dotnet::Nuget do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions
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
  let(:dependency_requirements) do
    [{ file: "my.csproj", requirement: "1.1.1", groups: [], source: nil }]
  end
  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:dependency_version) { "1.1.1" }

  let(:dependency_files) { [csproj] }
  let(:csproj) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:csproj_body) { fixture("dotnet", "csproj", "basic.csproj") }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:ignored_versions) { [] }

  let(:nuget_versions_url) do
    "https://api.nuget.org/v3-flatcontainer/"\
    "microsoft.extensions.dependencymodel/index.json"
  end
  let(:version_class) { Dependabot::Utils::Java::Version }
  let(:nuget_versions) do
    fixture("dotnet", "nuget_responses", "versions.json")
  end

  before do
    stub_request(:get, nuget_versions_url).
      to_return(status: 200, body: nuget_versions)
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(version_class.new("2.1.0")) }
  end
end
