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

  let(:files) { [csproj_file] + additional_files }
  let(:additional_files) { [] }
  let(:csproj_file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:csproj_body) { fixture("csproj", "basic.csproj") }
  let(:repo_contents_path) { write_tmp_repo(files) }
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

  describe "parse" do
    let(:dependencies) { parser.parse }

    subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

    context "with a single project file" do
      before do
        stub_search_results_with_versions_v3("microsoft.extensions.dependencymodel", ["1.0.1", "1.1.1"])
        stub_search_results_with_versions_v3("microsoft.aspnetcore.app", [])
        stub_search_results_with_versions_v3("microsoft.net.test.sdk", [])
        stub_search_results_with_versions_v3("microsoft.extensions.platformabstractions", ["1.1.0"])
        stub_search_results_with_versions_v3("system.collections.specialized", ["4.3.0"])
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
      let(:additional_files) { [vbproj_file] }
      let(:vbproj_file) do
        Dependabot::DependencyFile.new(
          name: "my.vbproj",
          content: fixture("csproj", "basic2.csproj")
        )
      end

      before do
        stub_search_results_with_versions_v3("microsoft.extensions.dependencymodel", ["1.0.1", "1.1.1"])
        stub_search_results_with_versions_v3("microsoft.aspnetcore.app", [])
        stub_search_results_with_versions_v3("microsoft.net.test.sdk", [])
        stub_search_results_with_versions_v3("microsoft.extensions.platformabstractions", ["1.1.0"])
        stub_search_results_with_versions_v3("system.collections.specialized", ["4.3.0"])
        stub_search_results_with_versions_v3("serilog", ["2.3.0"])
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
      let(:additional_files) { [packages_config] }
      let(:packages_config) do
        Dependabot::DependencyFile.new(
          name: "packages.config",
          content: fixture("packages_configs", "packages.config")
        )
      end

      let(:csproj_body) do
        <<~XML
          <Project Sdk="Microsoft.NET.Sdk">
            <!-- there has to be a .csproj, but for packages.config scenarios, the contents don't matter -->
            <PropertyGroup>
              <TargetFramework>netstandard2.0</TargetFramework>
            </PropertyGroup>
          </Project>
        XML
      end

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
        let(:packages_config) do
          Dependabot::DependencyFile.new(
            name: "dir/packages.config",
            content: fixture("packages_configs", "packages.config")
          )
        end
        let(:csproj_file) do
          Dependabot::DependencyFile.new(name: "dir/my.csproj", content: csproj_body)
        end

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
      let(:additional_files) { [global_json] }
      let(:global_json) do
        Dependabot::DependencyFile.new(
          name: "global.json",
          content: fixture("global_jsons", "global.json")
        )
      end

      its(:length) { is_expected.to eq(6) }

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
      let(:additional_files) { [dotnet_tools_json] }
      let(:dotnet_tools_json) do
        Dependabot::DependencyFile.new(
          name: ".config/dotnet-tools.json",
          content: fixture("dotnet_tools_jsons", "dotnet-tools.json")
        )
      end

      its(:length) { is_expected.to eq(7) }

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
      let(:additional_files) { [imported_file] }
      let(:imported_file) do
        Dependabot::DependencyFile.new(
          name: "commonprops.props",
          content: fixture("csproj", "commonprops.props")
        )
      end

      let(:csproj_body) do
        <<~XML
          <Project Sdk="Microsoft.NET.Sdk">
            <PropertyGroup>
              <TargetFramework>netstandard1.6</TargetFramework>
            </PropertyGroup>
            <Import Project="commonprops.props" />
          </Project>
        XML
      end

      before do
        stub_search_results_with_versions_v3("serilog", ["2.3.0"])
      end

      its(:length) { is_expected.to eq(1) }

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
            }, {
              requirement: "2.3.0",
              file: "my.csproj",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a packages.props file" do
      let(:additional_files) { [packages_file] }
      let(:packages_file) do
        Dependabot::DependencyFile.new(
          name: "packages.props",
          content: fixture("csproj", "packages.props")
        )
      end

      let(:csproj_body) do
        <<~XML
          <Project Sdk="Microsoft.NET.Sdk">
            <PropertyGroup>
              <TargetFramework>netstandard1.6</TargetFramework>
            </PropertyGroup>
            <Import Project="packages.props" />
          </Project>
        XML
      end

      before do
        stub_search_results_with_versions_v3("microsoft.sourcelink.github", ["1.0.0-beta2-19367-01"])
        stub_search_results_with_versions_v3("system.lycos", ["3.23.3"])
        stub_search_results_with_versions_v3("system.askjeeves", ["2.2.2"])
        stub_search_results_with_versions_v3("system.google", ["0.1.0-beta.3"])
        stub_search_results_with_versions_v3("system.webcrawler", ["1.1.1"])
      end

      its(:length) { is_expected.to eq(5) }

      describe "the System.WebCrawler dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "System.WebCrawler" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.WebCrawler")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "my.csproj",
              groups: ["dependencies"],
              source: nil
            }, {
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
      let(:additional_files) { [packages_file] }
      let(:packages_file) do
        Dependabot::DependencyFile.new(
          name: "Directory.Packages.props",
          content: fixture("csproj", "directory.packages.props")
        )
      end

      let(:csproj_body) do
        <<~XML
          <Project Sdk="Microsoft.NET.Sdk">
            <PropertyGroup>
              <TargetFramework>netstandard1.6</TargetFramework>
            </PropertyGroup>
            <ItemGroup>
              <PackageReference Include="System.Lycos" />
              <PackageReference Include="System.AskJeeves" />
              <PackageReference Include="System.Google" />
              <PackageReference Include="System.WebCrawler" />
            </ItemGroup>
          </Project>
        XML
      end

      before do
        stub_search_results_with_versions_v3("system.lycos", ["3.23.3"])
        stub_search_results_with_versions_v3("system.askjeeves", ["2.2.2"])
        stub_search_results_with_versions_v3("system.google", ["0.1.0-beta.3"])
        stub_search_results_with_versions_v3("system.webcrawler", ["1.1.1"])
      end

      its(:length) { is_expected.to eq(4) }

      describe "the System.WebCrawler dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "System.WebCrawler" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.WebCrawler")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "my.csproj",
              groups: ["dependencies"],
              source: nil
            }, {
              requirement: "1.1.1",
              file: "Directory.Packages.props",
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

      it do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "discovered dependencies are reported" do
      let(:csproj_file) do
        Dependabot::DependencyFile.new(
          name: "my.csproj",
          content:
            <<~XML
              <Project Sdk="Microsoft.NET.Sdk">
                <PropertyGroup>
                  <TargetFramework>net8.0</TargetFramework>
                  <SomePackageVersion>1.2.3</SomePackageVersion>
                </PropertyGroup>
                <ItemGroup>
                  <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                </ItemGroup>
              </Project>
            XML
        )
      end

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

    context "with a <TargetFramework> property that can't be evaluated" do
      let(:csproj_file) do
        Dependabot::DependencyFile.new(
          name: "my.csproj",
          content:
            <<~XML
              <Project Sdk="Microsoft.NET.Sdk">
                <PropertyGroup>
                  <TargetFramework>$(SomeCommonTfmThatCannotBeResolved)</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                  <PackageReference Include="Some.Package" Version="1.2.3" />
                </ItemGroup>
              </Project>
            XML
        )
      end

      before do
        allow(Dependabot.logger).to receive(:warn)
      end

      it "does not return the `.csproj` with an unresolvable TFM" do
        expect(dependencies.length).to eq(0)
      end
    end

    context "packages referenced in implicitly included `.targets` file are reported" do
      let(:additional_files) { [directory_build_targets] }
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
                </ItemGroup>
              </Project>
            XML
        )
      end
      let(:directory_build_targets) do
        Dependabot::DependencyFile.new(
          name: "Directory.Build.targets",
          content:
            <<~XML
              <Project>
                <ItemGroup>
                  <PackageReference Include="Package.B" Version="4.5.6" />
                </ItemGroup>
              </Project>
            XML
        )
      end

      before do
        stub_search_results_with_versions_v3("package.a", ["1.2.3"])
        stub_search_results_with_versions_v3("package.b", ["4.5.6"])
      end

      it "returns the correct dependency set" do
        expect(dependencies.length).to eq(2)
        expect(dependencies.map(&:name)).to match_array(%w(Package.A Package.B))
        expect(dependencies.map(&:version)).to match_array(%w(1.2.3 4.5.6))
      end
    end

    context "project <TargetFramework> element can be resolved from implicitly imported file" do
      let(:additional_files) { [directory_build_props] }
      let(:csproj_file) do
        Dependabot::DependencyFile.new(
          name: "my.csproj",
          content:
            <<~XML
              <Project Sdk="Microsoft.NET.Sdk">
                <PropertyGroup>
                  <TargetFramework>$(SomeTfm)</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                  <PackageReference Include="Package.A" Version="1.2.3" />
                </ItemGroup>
              </Project>
            XML
        )
      end
      let(:directory_build_props) do
        Dependabot::DependencyFile.new(
          name: "Directory.Build.props",
          content:
            <<~XML
              <Project>
                <PropertyGroup>
                  <SomeTfm>net8.0</SomeTfm>
                </PropertyGroup>
              </Project>
            XML
        )
      end

      before do
        stub_search_results_with_versions_v3("package.a", ["1.2.3"])
      end

      it "returns the correct dependency set" do
        expect(dependencies.length).to eq(1)
        expect(dependencies[0].name).to eq("Package.A")
        expect(dependencies[0].version).to eq("1.2.3")
      end
    end
  end
end
