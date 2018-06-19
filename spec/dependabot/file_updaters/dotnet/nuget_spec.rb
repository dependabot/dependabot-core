# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
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
      name: dependency_name,
      version: version,
      previous_version: previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "nuget"
    )
  end
  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:version) { "1.1.2" }
  let(:previous_version) { "1.1.1" }
  let(:requirements) do
    [{
      file: "my.csproj",
      requirement: "1.1.2",
      groups: [],
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "my.csproj",
      requirement: "1.1.1",
      groups: [],
      source: nil
    }]
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated csproj file" do
      subject(:updated_csproj_file) do
        updated_files.find { |f| f.name == "my.csproj" }
      end

      its(:content) { is_expected.to include 'Version="1.1.2" />' }
      its(:content) { is_expected.to include 'Version="1.1.0">' }

      it "doesn't update the formatting of the project file" do
        expect(updated_csproj_file.content).to include("</PropertyGroup>\n\n")
      end

      context "with a version range" do
        let(:csproj_body) { fixture("dotnet", "csproj", "ranges.csproj") }
        let(:dependency_name) { "Dep1" }
        let(:version) { "2.1" }
        let(:previous_version) { nil }
        let(:requirements) do
          [{
            file: "my.csproj",
            requirement: "[1.0,2.1]",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "my.csproj",
            requirement: "[1.0,2.0]",
            groups: [],
            source: nil
          }]
        end

        its(:content) { is_expected.to include '"Dep1" Version="[1.0,2.1]" />' }
      end
    end

    context "with a packages.config file" do
      let(:dependency_files) { [packages_config] }
      let(:packages_config) do
        Dependabot::DependencyFile.new(
          content: fixture("dotnet", "packages_configs", "packages.config"),
          name: "packages.config"
        )
      end
      let(:dependency_name) { "Newtonsoft.Json" }
      let(:version) { "8.0.4" }
      let(:previous_version) { "8.0.3" }
      let(:requirements) do
        [{
          file: "packages.config",
          requirement: "8.0.4",
          groups: [],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "packages.config",
          requirement: "8.0.3",
          groups: [],
          source: nil
        }]
      end

      describe "the updated packages.config file" do
        subject(:updated_packages_config_file) do
          updated_files.find { |f| f.name == "packages.config" }
        end

        its(:content) do
          is_expected.to include 'id="Newtonsoft.Json" version="8.0.4"'
        end
        its(:content) do
          is_expected.to include 'id="NuGet.Core" version="2.11.1"'
        end

        it "doesn't update the formatting of the project file" do
          expect(updated_packages_config_file.content).
            to include("</packages>\n\n")
        end
      end
    end

    context "with a vbproj and csproj" do
      let(:dependency_files) { [csproj_file, vbproj_file] }
      let(:vbproj_file) do
        Dependabot::DependencyFile.new(
          content: fixture("dotnet", "csproj", "basic2.csproj"),
          name: "my.vbproj"
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Microsoft.Extensions.DependencyModel",
          version: "1.1.2",
          previous_version: "1.1.1",
          requirements: [
            {
              file: "my.csproj",
              requirement: "1.1.2",
              groups: [],
              source: nil
            },
            {
              file: "my.vbproj",
              requirement: "1.1.*",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "my.csproj",
              requirement: "1.1.1",
              groups: [],
              source: nil
            },
            {
              file: "my.vbproj",
              requirement: "1.0.1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "nuget"
        )
      end

      describe "the updated csproj file" do
        subject(:updated_csproj_file) do
          updated_files.find { |f| f.name == "my.csproj" }
        end

        its(:content) { is_expected.to include 'Version="1.1.2" />' }
        its(:content) { is_expected.to include 'Version="1.1.0">' }
      end

      describe "the updated vbproj file" do
        subject(:updated_csproj_file) do
          updated_files.find { |f| f.name == "my.vbproj" }
        end

        its(:content) { is_expected.to include 'Version="1.1.*" />' }
      end
    end
  end
end
