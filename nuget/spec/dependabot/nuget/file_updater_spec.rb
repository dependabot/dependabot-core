# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Nuget::FileUpdater do
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
  let(:csproj_body) { fixture("csproj", "basic.csproj") }
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
      groups: ["dependencies"],
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "my.csproj",
      requirement: "1.1.1",
      groups: ["dependencies"],
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
      its(:content) { is_expected.to include 'version="1.1.0">' }

      it "doesn't update the formatting of the project file" do
        expect(updated_csproj_file.content).to include("</PropertyGroup>\n\n")
      end

      context "with a version range" do
        let(:csproj_body) { fixture("csproj", "ranges.csproj") }
        let(:dependency_name) { "Dep1" }
        let(:version) { "2.1" }
        let(:previous_version) { nil }
        let(:requirements) do
          [{
            file: "my.csproj",
            requirement: "[1.0,2.1]",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "my.csproj",
            requirement: "[1.0,2.0]",
            groups: ["dependencies"],
            source: nil
          }]
        end

        its(:content) { is_expected.to include '"Dep1" Version="[1.0,2.1]" />' }
      end

      context "with a property version" do
        let(:csproj_body) do
          fixture("csproj", "property_version.csproj")
        end
        let(:dependency_name) { "Nuke.Common" }
        let(:version) { "0.1.500" }
        let(:previous_version) { "0.1.434" }
        let(:requirements) do
          [{
            requirement: "0.1.500",
            file: "my.csproj",
            groups: ["dependencies"],
            source: nil,
            metadata: { property_name: "NukeVersion" }
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: "0.1.434",
            file: "my.csproj",
            groups: ["dependencies"],
            source: nil,
            metadata: { property_name: "NukeVersion" }
          }]
        end

        it "updates the property correctly" do
          expect(updated_csproj_file.content).to include(
            %(NukeVersion Condition="$(NukeVersion) == ''">0.1.500</NukeVersion)
          )
        end
      end

      context "with MSBuild SDKs" do
        let(:csproj_body) do
          fixture("csproj", "sdk_references_of_all_kinds.csproj")
        end
        let(:dependency_name) { "Foo.Bar" }
        let(:version) { "1.2.3" }
        let(:previous_version) { "1.1.1" }
        let(:requirements) do
          [{
            requirement: "1.2.3",
            file: "my.csproj",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: "1.1.1",
            file: "my.csproj",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "updates the project correctly" do
          content = updated_csproj_file.content
          # Sdk attribute on Project (front, middle, back)
          expect(content).to include(%(Sdk="Foo.Bar/1.2.3;))
          expect(content).to include(%(X;Foo.Bar/1.2.3;Y))
          expect(content).to include(%(Y;Foo.Bar/1.2.3">))
          # Sdk tag (name/version and version/name)
          expect(content).to include(%(<Sdk Version="1.2.3" Name="Foo.Bar"))
          expect(content).to include(%(<Sdk Name="Foo.Bar" Version="1.2.3"))
          # Import tag (name/version and version/name)
          expect(content).to include(
            %(<Import Project="X" Version="1.2.3" Sdk="Foo.Bar")
          )
          expect(content).to include(
            %(<Import Sdk="Foo.Bar" Project="Y" Version="1.2.3")
          )
        end
      end
    end

    context "with a packages.config file" do
      let(:dependency_files) { [packages_config] }
      let(:packages_config) do
        Dependabot::DependencyFile.new(
          content: fixture("packages_configs", "packages.config"),
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
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "packages.config",
          requirement: "8.0.3",
          groups: ["dependencies"],
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

      context "that is nested" do
        let(:packages_config) do
          Dependabot::DependencyFile.new(
            content: fixture("packages_configs", "packages.config"),
            name: "dir/packages.config"
          )
        end
        let(:requirements) do
          [{
            file: "dir/packages.config",
            requirement: "8.0.4",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "dir/packages.config",
            requirement: "8.0.3",
            groups: ["dependencies"],
            source: nil
          }]
        end

        describe "the updated packages.config file" do
          subject(:updated_packages_config_file) do
            updated_files.find { |f| f.name == "dir/packages.config" }
          end

          its(:content) do
            is_expected.to include 'id="Newtonsoft.Json" version="8.0.4"'
          end
          its(:content) do
            is_expected.to include 'id="NuGet.Core" version="2.11.1"'
          end
        end
      end
    end

    context "with a vbproj and csproj" do
      let(:dependency_files) { [csproj_file, vbproj_file] }
      let(:vbproj_file) do
        Dependabot::DependencyFile.new(
          content: fixture("csproj", "basic2.csproj"),
          name: "my.vbproj"
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Microsoft.Extensions.DependencyModel",
          version: "1.1.2",
          previous_version: "1.1.1",
          requirements: [{
            file: "my.csproj",
            requirement: "1.1.2",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "my.vbproj",
            requirement: "1.1.*",
            groups: ["dependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "my.csproj",
            requirement: "1.1.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "my.vbproj",
            requirement: "1.0.1",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "nuget"
        )
      end

      describe "the updated csproj file" do
        subject(:updated_csproj_file) do
          updated_files.find { |f| f.name == "my.csproj" }
        end

        its(:content) { is_expected.to include 'Version="1.1.2" />' }
        its(:content) { is_expected.to include 'version="1.1.0">' }
      end

      describe "the updated vbproj file" do
        subject(:updated_csproj_file) do
          updated_files.find { |f| f.name == "my.vbproj" }
        end

        its(:content) { is_expected.to include 'Version="1.1.*" />' }
      end
    end

    context "with a global.json" do
      let(:dependency_files) { [csproj_file, global_json] }
      let(:global_json) do
        Dependabot::DependencyFile.new(
          content: fixture("global_jsons", "global.json"),
          name: "global.json"
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Microsoft.Build.Traversal",
          version: "1.0.52",
          previous_version: "1.0.45",
          requirements: [{
            file: "global.json",
            requirement: "1.0.52",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "global.json",
            requirement: "1.0.45",
            groups: [],
            source: nil
          }],
          package_manager: "nuget"
        )
      end

      describe "the updated global.json file" do
        subject(:updated_global_json_file) do
          updated_files.find { |f| f.name == "global.json" }
        end

        its(:content) do
          is_expected.to include '"Microsoft.Build.Traversal": "1.0.52"'
        end
      end
    end
  end
end
