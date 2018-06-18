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
  let(:version_class) { Dependabot::Utils::Dotnet::Version }
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

    context "when the user wants a pre-release" do
      let(:dependency_version) { "2.2.0-preview1-26216-03" }
      it { is_expected.to eq(version_class.new("2.2.0-preview2-26406-04")) }
    end

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 2.a, < 3.0.0"] }
      it { is_expected.to eq(version_class.new("1.1.2")) }
    end

    context "with a custom repo in a nuget.config file" do
      let(:config_file) do
        Dependabot::DependencyFile.new(
          name: "NuGet.Config",
          content: fixture("dotnet", "configs", "nuget.config")
        )
      end
      let(:dependency_files) { [csproj, config_file] }
      before do
        repo_url = "https://www.myget.org/F/exceptionless/api/v3/index.json"
        stub_request(:get, repo_url).to_return(
          status: 200,
          body: fixture("dotnet", "nuget_responses", "myget_base.json")
        )
        stub_request(:get, nuget_versions_url).to_return(status: 404)
        custom_nuget_versions_url =
          "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/"\
          "microsoft.extensions.dependencymodel/index.json"
        stub_request(:get, custom_nuget_versions_url).
          to_return(status: 200, body: nuget_versions)
      end

      it { is_expected.to eq(version_class.new("2.1.0")) }
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "delegates to latest_version" do
      expect(checker).to receive(:latest_version).and_return("latest_version")
      expect(latest_resolvable_version).to eq("latest_version")
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.latest_resolvable_version_with_no_unlock }
    it { is_expected.to be_nil }
  end
end
