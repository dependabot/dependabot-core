# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/nuget/file_parser"
require_relative "nuget_search_stubs"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Nuget::FileParser do
  RSpec.configure do |config|
    config.include(NuGetSearchStubs)
  end

  it_behaves_like "a dependency file parser"

  let(:files) { [csproj_file] }
  let(:csproj_file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:csproj_body) { fixture("csproj", "basic.csproj") }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  def dependencies_from_info(deps_info)
    deps = deps_info.map do |info|
      Dependabot::Dependency.new(
        name: info[:name],
        version: info[:version],
        requirements: [
          {
            requirement: info[:version],
            file: info[:file],
            groups: ["dependencies"],
            source: nil
          }
        ],
        package_manager: "nuget"
      )
    end

    Dependabot::FileParsers::Base::DependencySet.new(deps)
  end

  describe "parse" do
    let(:dependencies) { parser.parse }
    subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

    context "with a .proj file" do
      let(:files) { [proj_file] }
      let(:proj_file) do
        Dependabot::DependencyFile.new(
          name: "proj.proj",
          content: fixture("csproj", "basic2.csproj")
        )
      end

      let(:proj_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.0.1", file: "proj.proj" },
          { name: "Serilog", version: "2.3.0", file: "proj.proj" }
        ]
      end

      before do
        dummy_project_file_parser = instance_double(described_class::ProjectFileParser)
        allow(parser).to receive(:project_file_parser).and_return(dummy_project_file_parser)
        allow(dummy_project_file_parser).to receive(:dependency_set).with(project_file: proj_file).and_return(
          dependencies_from_info(proj_dependencies)
        )
      end
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { top_level_dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Extensions.DependencyModel")
          expect(dependency.version).to eq("1.0.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.1",
              file: "proj.proj",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end

      describe "the last dependency" do
        subject(:dependency) { top_level_dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Serilog")
          expect(dependency.version).to eq("2.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.3.0",
              file: "proj.proj",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a single project file" do
      let(:project_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.1.1", file: "my.csproj" },
          { name: "Microsoft.AspNetCore.App", version: nil, file: "my.csproj" },
          { name: "Microsoft.NET.Test.Sdk", version: nil, file: "my.csproj" },
          { name: "Microsoft.Extensions.PlatformAbstractions", version: "1.1.0", file: "my.csproj" },
          { name: "System.Collections.Specialized", version: "4.3.0", file: "my.csproj" }
        ]
      end

      before do
        dummy_project_file_parser = instance_double(described_class::ProjectFileParser)
        allow(parser).to receive(:project_file_parser).and_return(dummy_project_file_parser)
        allow(dummy_project_file_parser).to receive(:dependency_set).and_return(
          dependencies_from_info(project_dependencies)
        )
      end
      its(:length) { is_expected.to eq(5) }

      describe "the first dependency" do
        subject(:dependency) { top_level_dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Extensions.DependencyModel")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "my.csproj",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end

      describe "the last dependency" do
        subject(:dependency) { top_level_dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.Collections.Specialized")
          expect(dependency.version).to eq("4.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.3.0",
              file: "my.csproj",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a csproj and a vbproj" do
      let(:files) { [csproj_file, vbproj_file] }
      let(:vbproj_file) do
        Dependabot::DependencyFile.new(
          name: "my.vbproj",
          content: fixture("csproj", "basic2.csproj")
        )
      end

      let(:csproj_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.1.1", file: "my.csproj" },
          { name: "Microsoft.AspNetCore.App", version: nil, file: "my.csproj" },
          { name: "Microsoft.NET.Test.Sdk", version: nil, file: "my.csproj" },
          { name: "Microsoft.Extensions.PlatformAbstractions", version: "1.1.0", file: "my.csproj" },
          { name: "System.Collections.Specialized", version: "4.3.0", file: "my.csproj" }
        ]
      end

      let(:vbproj_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.0.1", file: "my.vbproj" },
          { name: "Serilog", version: "2.3.0", file: "my.vbproj" }
        ]
      end

      before do
        dummy_project_file_parser = instance_double(described_class::ProjectFileParser)
        allow(parser).to receive(:project_file_parser).and_return(dummy_project_file_parser)
        allow(dummy_project_file_parser).to receive(:dependency_set).with(project_file: csproj_file).and_return(
          dependencies_from_info(csproj_dependencies)
        )
        allow(dummy_project_file_parser).to receive(:dependency_set).with(project_file: vbproj_file).and_return(
          dependencies_from_info(vbproj_dependencies)
        )
      end
      its(:length) { is_expected.to eq(6) }

      describe "the first dependency" do
        subject(:dependency) { top_level_dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Extensions.DependencyModel")
          expect(dependency.version).to eq("1.0.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "my.csproj",
              groups: ["dependencies"],
              source: nil
            }, {
              requirement: "1.0.1",
              file: "my.vbproj",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end

      describe "the last dependency" do
        subject(:dependency) { top_level_dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Serilog")
          expect(dependency.version).to eq("2.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.3.0",
              file: "my.vbproj",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a packages.config" do
      let(:files) { [packages_config] }
      let(:packages_config) do
        Dependabot::DependencyFile.new(
          name: "packages.config",
          content: fixture("packages_configs", "packages.config")
        )
      end

      its(:length) { is_expected.to eq(9) }

      describe "the first dependency" do
        subject(:dependency) { top_level_dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("Microsoft.CodeDom.Providers.DotNetCompilerPlatform")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.0",
              file: "packages.config",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end

      describe "the second dependency" do
        subject(:dependency) { top_level_dependencies.at(1) }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("Microsoft.Net.Compilers")
          expect(dependency.version).to eq("1.0.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.1",
              file: "packages.config",
              groups: ["devDependencies"],
              source: nil
            }]
          )
        end
      end

      context "that is nested" do
        its(:length) { is_expected.to eq(9) }
        let(:packages_config) do
          Dependabot::DependencyFile.new(
            name: "dir/packages.config",
            content: fixture("packages_configs", "packages.config")
          )
        end

        describe "the first dependency" do
          subject(:dependency) { top_level_dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name)
              .to eq("Microsoft.CodeDom.Providers.DotNetCompilerPlatform")
            expect(dependency.version).to eq("1.0.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.0.0",
                file: "dir/packages.config",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end

        describe "the second dependency" do
          subject(:dependency) { top_level_dependencies.at(1) }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name)
              .to eq("Microsoft.Net.Compilers")
            expect(dependency.version).to eq("1.0.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.0.1",
                file: "dir/packages.config",
                groups: ["devDependencies"],
                source: nil
              }]
            )
          end
        end
      end
    end

    context "with a global.json" do
      let(:files) { [packages_config, global_json] }
      let(:packages_config) do
        Dependabot::DependencyFile.new(
          name: "packages.config",
          content: fixture("packages_configs", "packages.config")
        )
      end
      let(:global_json) do
        Dependabot::DependencyFile.new(
          name: "global.json",
          content: fixture("global_jsons", "global.json")
        )
      end

      its(:length) { is_expected.to eq(10) }

      describe "the last dependency" do
        subject(:dependency) { top_level_dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Build.Traversal")
          expect(dependency.version).to eq("1.0.45")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.45",
              file: "global.json",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a dotnet-tools.json" do
      let(:files) { [packages_config, dotnet_tools_json] }
      let(:packages_config) do
        Dependabot::DependencyFile.new(
          name: "packages.config",
          content: fixture("packages_configs", "packages.config")
        )
      end
      let(:dotnet_tools_json) do
        Dependabot::DependencyFile.new(
          name: ".config/dotnet-tools.json",
          content: fixture("dotnet_tools_jsons", "dotnet-tools.json")
        )
      end

      its(:length) { is_expected.to eq(11) }

      describe "the last dependency" do
        subject(:dependency) { top_level_dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("dotnetsay")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.0",
              file: ".config/dotnet-tools.json",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with an imported properties file" do
      let(:files) { [csproj_file, imported_file] }
      let(:imported_file) do
        Dependabot::DependencyFile.new(
          name: "commonprops.props",
          content: fixture("csproj", "commonprops.props")
        )
      end

      let(:csproj_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.1.1", file: "my.csproj" },
          { name: "Microsoft.AspNetCore.App", version: nil, file: "my.csproj" },
          { name: "Microsoft.NET.Test.Sdk", version: nil, file: "my.csproj" },
          { name: "Microsoft.Extensions.PlatformAbstractions", version: "1.1.0", file: "my.csproj" },
          { name: "System.Collections.Specialized", version: "4.3.0", file: "my.csproj" }
        ]
      end

      let(:imported_file_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.0.1", file: "commonprops.props" },
          { name: "Serilog", version: "2.3.0", file: "commonprops.props" }
        ]
      end

      before do
        dummy_project_file_parser = instance_double(described_class::ProjectFileParser)
        allow(parser).to receive(:project_file_parser).and_return(dummy_project_file_parser)
        expect(dummy_project_file_parser).to receive(:dependency_set).with(project_file: csproj_file).and_return(
          dependencies_from_info(csproj_dependencies)
        )
        expect(dummy_project_file_parser).to receive(:dependency_set).with(project_file: imported_file).and_return(
          dependencies_from_info(imported_file_dependencies)
        )
      end

      its(:length) { is_expected.to eq(6) }

      describe "the last dependency" do
        subject(:dependency) { top_level_dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Serilog")
          expect(dependency.version).to eq("2.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.3.0",
              file: "commonprops.props",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a packages.props file" do
      let(:files) { [csproj_file, packages_file] }
      let(:packages_file) do
        Dependabot::DependencyFile.new(
          name: "packages.props",
          content: fixture("csproj", "packages.props")
        )
      end

      let(:csproj_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.1.1", file: "my.csproj" },
          { name: "Microsoft.AspNetCore.App", version: nil, file: "my.csproj" },
          { name: "Microsoft.NET.Test.Sdk", version: nil, file: "my.csproj" },
          { name: "Microsoft.Extensions.PlatformAbstractions", version: "1.1.0", file: "my.csproj" },
          { name: "System.Collections.Specialized", version: "4.3.0", file: "my.csproj" }
        ]
      end

      let(:packages_file_dependencies) do
        [
          { name: "Microsoft.SourceLink.GitHub", version: "1.0.0-beta2-19367-01", file: "packages.props" },
          { name: "System.Lycos", version: "3.23.3", file: "packages.props" },
          { name: "System.AskJeeves", version: "2.2.2", file: "packages.props" },
          { name: "System.Google", version: "0.1.0-beta.3", file: "packages.props" },
          { name: "System.WebCrawler", version: "1.1.1", file: "packages.props" }
        ]
      end

      before do
        dummy_project_file_parser = instance_double(described_class::ProjectFileParser)
        allow(parser).to receive(:project_file_parser).and_return(dummy_project_file_parser)
        expect(dummy_project_file_parser).to receive(:dependency_set).with(project_file: csproj_file).and_return(
          dependencies_from_info(csproj_dependencies)
        )
        expect(dummy_project_file_parser).to receive(:dependency_set).with(project_file: packages_file).and_return(
          dependencies_from_info(packages_file_dependencies)
        )
      end

      its(:length) { is_expected.to eq(10) }

      describe "the last dependency" do
        subject(:dependency) { top_level_dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.WebCrawler")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "packages.props",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a directory.packages.props file" do
      let(:files) { [csproj_file, packages_file] }
      let(:packages_file) do
        Dependabot::DependencyFile.new(
          name: "directory.packages.props",
          content: fixture("csproj", "directory.packages.props")
        )
      end

      let(:csproj_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.1.1", file: "my.csproj" },
          { name: "Microsoft.AspNetCore.App", version: nil, file: "my.csproj" },
          { name: "Microsoft.NET.Test.Sdk", version: nil, file: "my.csproj" },
          { name: "Microsoft.Extensions.PlatformAbstractions", version: "1.1.0", file: "my.csproj" },
          { name: "System.Collections.Specialized", version: "4.3.0", file: "my.csproj" }
        ]
      end

      let(:packages_file_dependencies) do
        [
          { name: "Microsoft.SourceLink.GitHub", version: "1.0.0-beta2-19367-01", file: "directory.packages.props" },
          { name: "System.Lycos", version: "3.23.3", file: "directory.packages.props" },
          { name: "System.AskJeeves", version: "2.2.2", file: "directory.packages.props" },
          { name: "System.WebCrawler", version: "1.1.1", file: "directory.packages.props" }
        ]
      end

      before do
        dummy_project_file_parser = instance_double(described_class::ProjectFileParser)
        allow(parser).to receive(:project_file_parser).and_return(dummy_project_file_parser)
        expect(dummy_project_file_parser).to receive(:dependency_set).with(project_file: csproj_file).and_return(
          dependencies_from_info(csproj_dependencies)
        )
        expect(dummy_project_file_parser).to receive(:dependency_set).with(project_file: packages_file).and_return(
          dependencies_from_info(packages_file_dependencies)
        )
      end

      its(:length) { is_expected.to eq(9) }

      describe "the last dependency" do
        subject(:dependency) { top_level_dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.WebCrawler")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "directory.packages.props",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with only directory.packages.props file" do
      let(:files) { [packages_file] }
      let(:packages_file) do
        Dependabot::DependencyFile.new(
          name: "directory.packages.props",
          content: fixture("csproj", "directory.packages.props")
        )
      end

      let(:packages_file_dependencies) do
        [
          { name: "Microsoft.SourceLink.GitHub", version: "1.0.0-beta2-19367-01", file: "directory.packages.props" },
          { name: "System.Lycos", version: "3.23.3", file: "directory.packages.props" },
          { name: "System.AskJeeves", version: "2.2.2", file: "directory.packages.props" },
          { name: "System.WebCrawler", version: "1.1.1", file: "directory.packages.props" }
        ]
      end

      before do
        dummy_project_file_parser = instance_double(described_class::ProjectFileParser)
        allow(parser).to receive(:project_file_parser).and_return(dummy_project_file_parser)
        expect(dummy_project_file_parser).to receive(:dependency_set).with(project_file: packages_file).and_return(
          dependencies_from_info(packages_file_dependencies)
        )
      end

      its(:length) { is_expected.to eq(4) }

      describe "the last dependency" do
        subject(:dependency) { top_level_dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.WebCrawler")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "directory.packages.props",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with unparsable dependency versions" do
      let(:csproj_file) do
        Dependabot::DependencyFile.new(
          name: "my.csproj",
          content:
            <<~XML
              <Project Sdk="Microsoft.NET.Sdk">
                <PropertyGroup>
                  <TargetFramework>net8.0</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                  <PackageReference Include="Package.A" Version="1.2.3" />
                  <PackageReference Include="Package.B" Version="$(ThisPropertyCannotBeResolved)" />
                </ItemGroup>
              </Project>
            XML
        )
      end

      before do
        allow(Dependabot.logger).to receive(:warn)
        stub_search_results_with_versions_v3("package.a", ["1.2.3"])
        stub_search_results_with_versions_v3("package.b", ["4.5.6"])
        stub_request(:get, "https://api.nuget.org/v3-flatcontainer/package.a/1.2.3/package.a.nuspec")
          .to_return(
            status: 200,
            body:
              <<~XML
                <package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
                  <metadata>
                    <id>Package.A</id>
                    <version>1.2.3</version>
                    <dependencies>
                      <group targetFramework="net8.0">
                      </group>
                    </dependencies>
                  </metadata>
                </package>
              XML
          )
      end

      it "returns only actionable dependencies" do
        expect(dependencies.length).to eq(1)
        expect(dependencies[0].name).to eq("Package.A")
        expect(dependencies[0].version).to eq("1.2.3")
        expect(Dependabot.logger).to have_received(:warn).with(
          "Dependency 'Package.B' excluded due to unparsable version: $ThisPropertyCannotBeResolved"
        )
      end
    end
  end
end
