# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/nuget/file_parser"
require "dependabot/nuget/version"
require_relative "nuget_search_stubs"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Nuget::FileParser do
  RSpec.configure do |config|
    config.include(NuGetSearchStubs)
  end

  it_behaves_like "a dependency file parser"
  let(:project_name) { "file_parser_csproj" }
  let(:directory) { "/" }
  # project_dependency files comes back with directory files first, we need the closest project at the top
  let(:files) { nuget_project_dependency_files(project_name, directory: directory).reverse }
  let(:repo_contents_path) { nuget_build_tmp_repo(project_name) }
  let(:parser) do
    described_class.new(dependency_files: files,
                        source: source,
                        repo_contents_path: repo_contents_path)
  end
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
      let(:project_name) { "file_parser_proj" }

      let(:proj_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.0.1", file: "proj.proj" },
          { name: "Serilog", version: "2.3.0", file: "proj.proj" }
        ]
      end

      its(:length) { is_expected.to eq(2) }

      describe "the Microsoft.Extensions.DependencyModel dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "Microsoft.Extensions.DependencyModel" } }

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

      describe "the Serilog dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "Serilog" } }

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

      its(:length) { is_expected.to eq(5) }

      describe "the Microsoft.Extensions.DependencyModel dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "Microsoft.Extensions.DependencyModel" } }

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

      describe "the System.Collections.Specialized dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "System.Collections.Specialized" } }

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
      let(:project_name) { "file_parser_csproj_vbproj" }

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

      its(:length) { is_expected.to eq(6) }

      describe "the Microsoft.Extensions.DependencyModel dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "Microsoft.Extensions.DependencyModel" } }

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

      describe "the Serilog dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "Serilog" } }

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
      let(:project_name) { "file_parser_packages_config" }

      its(:length) { is_expected.to eq(9) }

      describe "the Microsoft.CodeDom.Providers.DotNetCompilerPlatform dependency" do
        subject(:dependency) do
          dependencies.find do |d|
            d.name == "Microsoft.CodeDom.Providers.DotNetCompilerPlatform"
          end
        end

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

      describe "the Microsoft.Net.Compilers dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "Microsoft.Net.Compilers" } }

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
        let(:project_name) { "file_parser_packages_config_nested" }
        its(:length) { is_expected.to eq(9) }

        describe "the Microsoft.CodeDom.Providers.DotNetCompilerPlatform dependency" do
          subject(:dependency) do
            dependencies.find do |d|
              d.name == "Microsoft.CodeDom.Providers.DotNetCompilerPlatform"
            end
          end

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

        describe "the Microsoft.Net.Compilers dependency" do
          subject(:dependency) { dependencies.find { |d| d.name == "Microsoft.Net.Compilers" } }

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
      let(:project_name) { "file_parser_packages_config_global_json" }

      its(:length) { is_expected.to eq(10) }

      describe "the Microsoft.Build.Traversal dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "Microsoft.Build.Traversal" } }

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
      let(:project_name) { "file_parser_packages_config_dotnet_tools_json" }

      its(:length) { is_expected.to eq(11) }

      describe "the dotnetsay dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "dotnetsay" } }

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
      let(:project_name) { "file_parser_csproj_imported_props" }

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

      its(:length) { is_expected.to eq(6) }

      describe "the Serilog dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "Serilog" } }

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
      let(:project_name) { "file_parser_csproj_packages_props" }

      let(:csproj_dependencies) do
        [
          { name: "Microsoft.Extensions.DependencyModel", version: "1.1.1", file: "my.csproj" },
          { name: "Microsoft.AspNetCore.App", version: nil, file: "my.csproj" },
          { name: "Microsoft.NET.Test.Sdk", version: nil, file: "my.csproj" },
          { name: "Microsoft.Extensions.PlatformAbstractions", version: "1.1.0", file: "my.csproj" },
          { name: "System.Collections.Specialized", version: "4.3.0", file: "my.csproj" }
        ]
      end

      let(:directory_build_dependencies) do
        [
          { name: "Microsoft.Build.CentralPackageVersions", version: "2.1.3", file: "Directory.Build.targets" }
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

      its(:length) { is_expected.to eq(11) }

      describe "the System.WebCrawler dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "System.WebCrawler" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.WebCrawler")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "Packages.props",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a directory.packages.props file" do
      let(:project_name) { "file_parser_csproj_directory_packages_props" }

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

      its(:length) { is_expected.to eq(9) }

      describe "the System.WebCrawler dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "System.WebCrawler" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.WebCrawler")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "Directory.Packages.props",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "discovered dependencies are reported" do
      let(:project_name) { "file_parser_csproj_property" }

      before do
        allow(Dependabot.logger).to receive(:info)
        stub_search_results_with_versions_v3("some.package", ["1.2.3"])
        stub_request(:get, "https://api.nuget.org/v3-flatcontainer/some.package/1.2.3/some.package.nuspec")
          .to_return(
            status: 200,
            body:
              <<~XML
                <package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
                  <metadata>
                    <id>Some.Package</id>
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

      it "reports the relevant information" do
        expect(dependencies.length).to eq(1) # this line is really just to force evaluation so we can see the infos
        expect(Dependabot.logger).to have_received(:info).with(
          <<~INFO
            Discovery JSON content: {
              "FilePath": "",
              "IsSuccess": true,
              "Projects": [
                {
                  "FilePath": "my.csproj",
                  "Dependencies": [
                    {
                      "Name": "Microsoft.NET.Sdk",
                      "Version": null,
                      "Type": "MSBuildSdk",
                      "EvaluationResult": null,
                      "TargetFrameworks": null,
                      "IsDevDependency": false,
                      "IsDirect": false,
                      "IsTransitive": false,
                      "IsOverride": false,
                      "IsUpdate": false
                    },
                    {
                      "Name": "Some.Package",
                      "Version": "1.2.3",
                      "Type": "PackageReference",
                      "EvaluationResult": {
                        "ResultType": "Success",
                        "OriginalValue": "$(SomePackageVersion)",
                        "EvaluatedValue": "1.2.3",
                        "RootPropertyName": "SomePackageVersion",
                        "ErrorMessage": null
                      },
                      "TargetFrameworks": [
                        "net8.0"
                      ],
                      "IsDevDependency": false,
                      "IsDirect": true,
                      "IsTransitive": false,
                      "IsOverride": false,
                      "IsUpdate": false
                    }
                  ],
                  "IsSuccess": true,
                  "Properties": [
                    {
                      "Name": "SomePackageVersion",
                      "Value": "1.2.3",
                      "SourceFilePath": "my.csproj"
                    },
                    {
                      "Name": "TargetFramework",
                      "Value": "net8.0",
                      "SourceFilePath": "my.csproj"
                    }
                  ],
                  "TargetFrameworks": [
                    "net8.0"
                  ],
                  "ReferencedProjectPaths": []
                }
              ],
              "DirectoryPackagesProps": null,
              "GlobalJson": null,
              "DotNetToolsJson": null
            }
          INFO
          .chomp
        )
      end
    end

    context "with unparsable dependency versions" do
      let(:project_name) { "file_parser_csproj_unparsable" }

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

      its(:length) { is_expected.to eq(1) }

      describe "the Package.A dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "Package.A" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Package.A")
          expect(dependency.version).to eq("1.2.3")
          expect(Dependabot.logger).to have_received(:warn).with(
            "Dependency 'Package.B' excluded due to unparsable version: $(ThisPropertyCannotBeResolved)"
          )
        end
      end
    end
  end
end
