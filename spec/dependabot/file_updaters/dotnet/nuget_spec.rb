# frozen_string_literal: true

require "dependabot/file_updaters/dotnet/nuget"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Dotnet::Nuget do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end
  let(:dependency_files) { [csproj_file] }
  let(:dependencies) { [dependency] }
  let(:csproj_file) do
    Dependabot::DependencyFile.new(content: csproj_body, name: "my.csproj")
  end
  let(:csproj_body) { fixture("dotnet", "csproj", "basic.csproj") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Microsoft.Extensions.DependencyModel",
      version: "1.1.2",
      previous_version: "1.1.1",
      requirements: [{
        file: "my.csproj",
        requirement: "1.1.2",
        groups: [],
        source: nil
      }],
      previous_requirements: [{
        file: "my.csproj",
        requirement: "1.1.1",
        groups: [],
        source: nil
      }],
      package_manager: "nuget"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated csproj file" do
      subject(:updated_pom_file) do
        updated_files.find { |f| f.name == "my.csproj" }
      end

      its(:content) { is_expected.to include 'Version="1.1.2" />' }
      its(:content) { is_expected.to include 'Version="1.1.0">' }

      it "doesn't update the formatting of the POM" do
        expect(updated_pom_file.content).to include("</PropertyGroup>\n\n")
      end
    end
  end
end
