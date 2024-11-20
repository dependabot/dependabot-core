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

  let(:stub_native_tools) { true } # set to `false` to allow invoking the native tools during tests
  let(:report_stub_debug_information) { false } # set to `true` to write native tool stubbing information to the screen

  let(:dependency_files) { [csproj_file] + additional_files }
  let(:additional_files) { [] }
  let(:csproj_file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:csproj_body) { fixture("csproj", "basic.csproj") }
  let(:repo_contents_path) { write_tmp_repo(dependency_files) }
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  let(:files) { [csproj_file] + additional_files }

  # the minimum job object required by the updater
  let(:job) do
    {
      job: {
        "allowed-updates": [
          { "update-type": "all" }
        ],
        "package-manager": "nuget",
        source: {
          provider: "github",
          repo: "gocardless/bump",
          directory: "/",
          branch: "main"
        }
      }
    }
  end

  it_behaves_like "a dependency file parser"

  def ensure_job_file(&_block)
    file = Tempfile.new
    begin
      File.write(file.path, job.to_json)
      ENV["DEPENDABOT_JOB_PATH"] = file.path
      puts "created temp job file at [#{file.path}]"
      yield
    ensure
      ENV.delete("DEPENDABOT_JOB_PATH")
      FileUtils.rm_f(file.path)
      puts "deleted temp job file at [#{file.path}]"
    end
  end

  def run_parser_test(&_block)
    # caching is explicitly required for these tests
    ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "false"

    # don't allow a previous test to pollute the file parser cache
    Dependabot::Nuget::FileParser.file_dependency_cache.clear

    # create the parser...
    parser = Dependabot::Nuget::FileParser.new(dependency_files: dependency_files,
                                               source: source,
                                               repo_contents_path: repo_contents_path)

    # ...and invoke the actual test
    ensure_job_file do
      yield parser
    end
  ensure
    Dependabot::Nuget::NativeDiscoveryJsonReader.clear_discovery_file_path_from_cache(dependency_files)
    ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "true"
  end

  def intercept_native_tools(discovery_content_hash:)
    return unless stub_native_tools

    # don't allow `FileParser#parse` to call into the native tool; just fake it
    allow(Dependabot::Nuget::NativeHelpers)
      .to receive(:run_nuget_discover_tool)
      .and_wrap_original do |_original_method, *args, &_block|
        discovery_json_path = args[0][:output_path]
        FileUtils.mkdir_p(File.dirname(discovery_json_path))
        if report_stub_debug_information
          puts "stubbing call to `run_nuget_discover_tool` with args #{args}; writing prefabricated discovery " \
               "response to discovery.json to #{discovery_json_path}"
        end
        discovery_json_content = discovery_content_hash.to_json
        File.write(discovery_json_path, discovery_json_content)
      end
  end

  describe "parse" do
    context "with a single project file" do
      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [{
              FilePath: "my.csproj",
              Dependencies: [{
                Name: "Microsoft.Extensions.DependencyModel",
                Version: "1.1.1",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net462"],
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }, {
                Name: "System.Collections.Specialized",
                Version: "4.3.0",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net462"],
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [{
                Name: "TargetFrameworks",
                Value: "net462",
                SourceFilePath: "my.csproj"
              }],
              TargetFrameworks: ["net462"],
              ReferencedProjectPaths: []
            }],
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      it "is returns the expected set of dependencies" do
        run_parser_test do |parser|
          dependencies = parser.parse
          expect(dependencies.length).to eq(2)

          dependency = dependencies.find { |d| d.name == "Microsoft.Extensions.DependencyModel" }
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq([{
            requirement: "1.1.1",
            file: "/my.csproj",
            groups: ["dependencies"],
            source: nil
          }])
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
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [{
              FilePath: "my.csproj",
              Dependencies: [{
                Name: "Microsoft.Extensions.DependencyModel",
                Version: "1.1.1",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net462"],
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [{
                Name: "TargetFrameworks",
                Value: "net462",
                SourceFilePath: "my.csproj"
              }],
              TargetFrameworks: ["net462"],
              ReferencedProjectPaths: []
            }, {
              FilePath: "my.vbproj",
              Dependencies: [{
                Name: "Microsoft.Extensions.DependencyModel",
                Version: "1.0.1",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net462"],
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [{
                Name: "TargetFrameworks",
                Value: "net462",
                SourceFilePath: "my.csproj"
              }],
              TargetFrameworks: ["net462"],
              ReferencedProjectPaths: []
            }],
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      it "reports the correct dependency information" do
        run_parser_test do |parser|
          dependencies = parser.parse
          dependency = dependencies.find { |d| d.name == "Microsoft.Extensions.DependencyModel" }
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Extensions.DependencyModel")
          expect(dependency.version).to eq("1.0.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "/my.csproj",
              groups: ["dependencies"],
              source: nil
            }, {
              requirement: "1.0.1",
              file: "/my.vbproj",
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

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [{
              FilePath: "my.csproj",
              Dependencies: [{
                Name: "Microsoft.CodeDom.Providers.DotNetCompilerPlatform",
                Version: "1.0.0",
                Type: "PackagesConfig",
                EvaluationResult: nil,
                TargetFrameworks: ["netstandard2.0"],
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [{
                Name: "TargetFramework",
                Value: "netstandard2.0",
                SourceFilePath: "my.csproj"
              }],
              TargetFrameworks: ["netstandard2.0"],
              ReferencedProjectPaths: []
            }],
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      it "reports the correct dependencies" do
        run_parser_test do |parser|
          dependencies = parser.parse
          dependency = dependencies.find { |d| d.name == "Microsoft.CodeDom.Providers.DotNetCompilerPlatform" }
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.0",
              file: "/packages.config",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end

      context "when it is nested" do
        let(:directory) { "/dir" }
        let(:packages_config) do
          Dependabot::DependencyFile.new(
            name: "dir/packages.config",
            content: fixture("packages_configs", "packages.config")
          )
        end
        let(:csproj_file) do
          Dependabot::DependencyFile.new(name: "dir/my.csproj", content: csproj_body)
        end

        before do
          intercept_native_tools(
            discovery_content_hash: {
              Path: "dir",
              IsSuccess: true,
              Projects: [{
                FilePath: "my.csproj",
                Dependencies: [{
                  Name: "Microsoft.CodeDom.Providers.DotNetCompilerPlatform",
                  Version: "1.0.0",
                  Type: "PackagesConfig",
                  EvaluationResult: nil,
                  TargetFrameworks: ["netstandard2.0"],
                  IsDevDependency: false,
                  IsDirect: false,
                  IsTransitive: false,
                  IsOverride: false,
                  IsUpdate: false,
                  InfoUrl: nil
                }],
                IsSuccess: true,
                Properties: [{
                  Name: "TargetFramework",
                  Value: "netstandard2.0",
                  SourceFilePath: "my.csproj"
                }],
                TargetFrameworks: ["netstandard2.0"],
                ReferencedProjectPaths: []
              }],
              ImportedFiles: [],
              GlobalJson: nil,
              DotNetToolsJson: nil
            }
          )
        end

        it "reports the correct results" do
          run_parser_test do |parser|
            dependencies = parser.parse
            dependency = dependencies.find { |d| d.name == "Microsoft.CodeDom.Providers.DotNetCompilerPlatform" }
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.version).to eq("1.0.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.0.0",
                file: "/dir/packages.config",
                groups: ["dependencies"],
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

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [], # not relevant for this test
            ImportedFiles: [],
            GlobalJson: {
              FilePath: "global.json",
              IsSuccess: true,
              Dependencies: [{
                Name: "Microsoft.Build.Traversal",
                Version: "1.0.45",
                Type: "MSBuildSdk",
                EvaluationResult: nil,
                TargetFrameworks: nil,
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }]
            },
            DotNetToolsJson: nil
          }
        )
      end

      it "reports the expected results" do
        run_parser_test do |parser|
          dependencies = parser.parse
          dependency = dependencies.find { |d| d.name == "Microsoft.Build.Traversal" }
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("1.0.45")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.45",
              file: "/global.json",
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

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [], # not relevant for this test
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: {
              FilePath: ".config/dotnet-tools.json",
              IsSuccess: true,
              Dependencies: [{
                Name: "dotnetsay",
                Version: "1.0.0",
                Type: "DotNetTool",
                EvaluationResult: nil,
                TargetFrameworks: nil,
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }]
            }
          }
        )
      end

      it "has the right details" do
        run_parser_test do |parser|
          dependencies = parser.parse
          dependency = dependencies.find { |d| d.name == "dotnetsay" }
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.0",
              file: "/.config/dotnet-tools.json",
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
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [{
              FilePath: "commonprops.props",
              Dependencies: [{
                Name: "Serilog",
                Version: "2.3.0",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: nil,
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [],
              TargetFrameworks: [],
              ReferencedProjectPaths: []
            }, {
              FilePath: "my.csproj",
              Dependencies: [{
                Name: "Serilog",
                Version: "2.3.0",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["netstandard1.6"],
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [{
                Name: "TargetFramework",
                Value: "netstandard1.6",
                SourceFilePath: "my.csproj"
              }],
              TargetFrameworks: ["netstandard1.6"],
              ReferencedProjectPaths: []
            }],
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      describe "the Serilog dependency" do
        it "has the right details" do
          run_parser_test do |parser|
            dependencies = parser.parse
            dependency = dependencies.find { |d| d.name == "Serilog" }
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("Serilog")
            expect(dependency.version).to eq("2.3.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "2.3.0",
                file: "/commonprops.props",
                groups: ["dependencies"],
                source: nil
              }, {
                requirement: "2.3.0",
                file: "/my.csproj",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
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
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [{
              FilePath: "my.csproj",
              Dependencies: [{
                Name: "System.WebCrawler",
                Version: "1.1.1",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["netstandard1.6"],
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: true,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [{
                Name: "TargetFramework",
                Value: "netstandard1.6",
                SourceFilePath: "my.csproj"
              }],
              TargetFrameworks: ["netstandard1.6"],
              ReferencedProjectPaths: []
            }, {
              FilePath: "packages.props",
              Dependencies: [{
                Name: "System.WebCrawler",
                Version: "1.1.1",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: nil,
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: true,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [],
              TargetFrameworks: [],
              ReferencedProjectPaths: []
            }],
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      describe "the System.WebCrawler dependency" do
        it "has the right details" do
          run_parser_test do |parser|
            dependencies = parser.parse
            dependency = dependencies.find { |d| d.name == "System.WebCrawler" }
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.version).to eq("1.1.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.1.1",
                file: "/my.csproj",
                groups: ["dependencies"],
                source: nil
              }, {
                requirement: "1.1.1",
                file: "/packages.props",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
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
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [{
              FilePath: "my.csproj",
              Dependencies: [{
                Name: "System.WebCrawler",
                Version: "1.1.1",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["netstandard1.6"],
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [{
                Name: "TargetFramework",
                Value: "netstandard1.6",
                SourceFilePath: "my.csproj"
              }],
              TargetFrameworks: ["netstandard1.6"],
              ReferencedProjectPaths: []
            }],
            ImportedFiles: ["Directory.Packages.props"],
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      describe "the System.WebCrawler dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "System.WebCrawler" } }

        it "has the right details" do
          run_parser_test do |parser|
            dependencies = parser.parse
            dependency = dependencies.find { |d| d.name == "System.WebCrawler" }
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.version).to eq("1.1.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.1.1",
                file: "/my.csproj",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end
    end

    context "with only directory.packages.props file" do
      let(:dependency_files) { [packages_file] }
      let(:packages_file) do
        Dependabot::DependencyFile.new(
          name: "directory.packages.props",
          content: fixture("csproj", "directory.packages.props")
        )
      end

      it "fails in the initializer" do
        expect do
          run_parser_test do |parser|
            _dependencies = parser.parse
          end
        end.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when discovered dependencies are reported" do
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
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [],
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      it "reports the relevant information" do
        run_parser_test do |parser|
          _dependencies = parser.parse # the result doesn't matter, but it forces discovery to run
          expect(Dependabot.logger).to have_received(:info).with(
            <<~INFO
              Discovery JSON content: {"Path":"","IsSuccess":true,"Projects":[],"ImportedFiles":[],"GlobalJson":null,"DotNetToolsJson":null}
            INFO
            .chomp
          )
        end
      end
    end

    context "when packages referenced in implicitly included `.targets` file are reported" do
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
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [{
              FilePath: "Directory.Build.targets",
              Dependencies: [{
                Name: "Package.B",
                Version: "4.5.6",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: nil,
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [],
              TargetFrameworks: [],
              ReferencedProjectPaths: []
            }, {
              FilePath: "my.csproj",
              Dependencies: [{
                Name: "Package.A",
                Version: "1.2.3",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net8.0"],
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }, {
                Name: "Package.B",
                Version: "4.5.6",
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net8.0"],
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [{
                Name: "TargetFramework",
                Value: "net8.0",
                SourceFilePath: "my.csproj"
              }],
              TargetFrameworks: ["net8.0"],
              ReferencedProjectPaths: []
            }],
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      it "returns the correct dependency set" do
        run_parser_test do |parser|
          dependencies = parser.parse
          expect(dependencies.length).to eq(2)
          expect(dependencies.map(&:name)).to match_array(%w(Package.A Package.B))
          expect(dependencies.map(&:version)).to match_array(%w(1.2.3 4.5.6))
        end
      end
    end

    context "when non-concrete version numbers are reported" do
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

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [{
              FilePath: "my.csproj",
              Dependencies: [{
                Name: "Package.A",
                Version: nil, # not reported without version
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net8.0"],
                IsDevDependency: false,
                IsDirect: true,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }, {
                Name: "Package.B",
                Version: "", # not reported with empty version
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net8.0"],
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }, {
                Name: "Package.C",
                Version: "[1.0,2.0)", # not reported with range
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net8.0"],
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }, {
                Name: "Package.D",
                Version: "1.*", # not reported with wildcard
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net8.0"],
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }, {
                Name: "Package.E",
                Version: "1.2.3", # regular version _is_ reported
                Type: "PackageReference",
                EvaluationResult: nil,
                TargetFrameworks: ["net8.0"],
                IsDevDependency: false,
                IsDirect: false,
                IsTransitive: false,
                IsOverride: false,
                IsUpdate: false,
                InfoUrl: nil
              }],
              IsSuccess: true,
              Properties: [{
                Name: "TargetFramework",
                Value: "net8.0",
                SourceFilePath: "my.csproj"
              }],
              TargetFrameworks: ["net8.0"],
              ReferencedProjectPaths: []
            }],
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      it "returns the correct dependency set" do
        run_parser_test do |parser|
          dependencies = parser.parse
          expect(dependencies.length).to eq(1)
          expect(dependencies[0].name).to eq("Package.E")
        end
      end
    end

    context "when there is a private source authentication failure" do
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

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: false,
            Projects: [],
            ImportedFiles: [],
            GlobalJson: nil,
            DotNetToolsJson: nil,
            ErrorType: "AuthenticationFailure",
            ErrorDetails: "the-error-details"
          }
        )
      end

      it "raises the correct error" do
        run_parser_test do |parser|
          expect { parser.parse }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
        end
      end
    end
  end
end
