# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/analysis/analysis_json_reader"
require "dependabot/nuget/native_discovery/native_discovery_json_reader"
require "dependabot/nuget/file_parser"
require "dependabot/nuget/update_checker"
require "dependabot/nuget/requirement"
require "dependabot/nuget/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Nuget::UpdateChecker do
  let(:version_class) { Dependabot::Nuget::Version }
  let(:security_advisories) { [] }
  let(:ignored_versions) { [] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:csproj_body) { fixture("csproj", "basic.csproj") }
  let(:csproj) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:dependency_files) { [csproj] }
  let(:dependency_version) { "1.1.1" }
  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:dependency_requirements) do
    [{ file: "my.csproj", requirement: "1.1.1", groups: ["dependencies"], source: nil }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "nuget"
    )
  end

  let(:stub_native_tools) { true } # set to `false` to allow invoking the native tools during tests
  let(:report_stub_debug_information) { false } # set to `true` to write native tool stubbing information to the screen

  let(:repo_contents_path) { write_tmp_repo(dependency_files) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  before do
    Dependabot::Experiments.register(:nuget_native_analysis, true)
  end

  it_behaves_like "an update checker"

  def run_analyze_test(&_block)
    # caching is explicitly required for these tests
    ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "false"

    # don't allow a previous test to pollute the file parser cache
    Dependabot::Nuget::FileParser.file_dependency_cache.clear

    # calling `#parse` is necessary to force `discover` which is stubbed below
    Dependabot::Nuget::FileParser.new(dependency_files: dependency_files,
                                      source: source,
                                      repo_contents_path: repo_contents_path).parse

    # create the checker...
    checker = described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      repo_contents_path: repo_contents_path,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )

    # ...and invoke the actual test
    yield checker
  ensure
    Dependabot::Nuget::NativeDiscoveryJsonReader.clear_discovery_file_path_from_cache(dependency_files)
    ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "true"
  end

  def registration_index_url(name)
    "https://api.nuget.org/v3/registration5-gz-semver2/#{name.downcase}/index.json"
  end

  def intercept_native_tools(discovery_content_hash:, dependency_name:, analysis_content_hash:)
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

    # prevent calling the analysis tool
    allow(Dependabot::Nuget::NativeHelpers)
      .to receive(:run_nuget_analyze_tool)
      .and_wrap_original do |_original_method, *args, &_block|
        # write prefabricated analysis json file
        analysis_json_path = Dependabot::Nuget::AnalysisJsonReader.analysis_file_path(dependency_name: dependency_name)
        if report_stub_debug_information
          puts "stubbing call to `run_nuget_analyze_tool` with args #{args}; writing prefabricated analysis response " \
               "to #{analysis_json_path}"
        end
        analysis_json_content = analysis_content_hash.to_json
        FileUtils.mkdir_p(File.dirname(analysis_json_path))
        File.write(analysis_json_path, analysis_json_content)
      end
  end

  describe "up_to_date?" do
    context "with a property dependency whose property couldn't be found" do
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_requirements) do
        [{
          requirement: "$(NukeVersion)",
          file: "my.csproj",
          groups: ["dependencies"],
          source: nil,
          metadata: { property_name: "NukeVersion" }
        }]
      end
      let(:dependency_version) { "$(NukeVersion)" }

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [
              {
                FilePath: "my.csproj",
                Dependencies: [], # dependency not found
                IsSuccess: true,
                Properties: [
                  {
                    Name: "TargetFrameworks",
                    Value: "netstandard1.6;net462",
                    SourceFilePath: "my.csproj"
                  }
                ],
                TargetFrameworks: ["net462", "netstandard1.6"],
                ReferencedProjectPaths: []
              }
            ],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Nuke.Common",
          analysis_content_hash: {
            UpdatedVersion: "$(NukeVersion)",
            CanUpdate: false,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: [],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          }
        )
      end

      it "reports the expected result" do
        run_analyze_test do |checker|
          expect(checker.up_to_date?).to be(true)
        end
      end
    end

    context "with a dependency that is not reported" do
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_requirements) { [] }
      let(:dependency_version) { "2.0.0" }

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [
              {
                FilePath: "my.csproj",
                Dependencies: [], # dependency not found
                IsSuccess: true,
                Properties: [
                  {
                    Name: "TargetFrameworks",
                    Value: "netstandard1.6;net462",
                    SourceFilePath: "my.csproj"
                  }
                ],
                TargetFrameworks: ["net462", "netstandard1.6"],
                ReferencedProjectPaths: []
              }
            ],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Nuke.Common",
          analysis_content_hash: {
            UpdatedVersion: "2.0.0",
            CanUpdate: false,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: []
          }
        )
      end

      it "reports the expected result" do
        run_analyze_test do |checker|
          expect(checker.up_to_date?).to be(true)
        end
      end
    end

    context "with a dependency that can be updated" do
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_requirements) { [] }
      let(:dependency_version) { "2.0.0" }

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [
              {
                FilePath: "my.csproj",
                Dependencies: [{
                  Name: "Nuke.Common",
                  Version: "2.0.0",
                  Type: "Unknown",
                  EvaluationResult: nil,
                  TargetFrameworks: ["net462", "netstandard1.6"],
                  IsDevDependency: false,
                  IsDirect: true,
                  IsTransitive: false,
                  IsOverride: false,
                  IsUpdate: false,
                  InfoUrl: nil
                }],
                IsSuccess: true,
                Properties: [
                  {
                    Name: "TargetFrameworks",
                    Value: "netstandard1.6;net462",
                    SourceFilePath: "my.csproj"
                  }
                ],
                TargetFrameworks: ["net462", "netstandard1.6"],
                ReferencedProjectPaths: []
              }
            ],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Nuke.Common",
          analysis_content_hash: {
            UpdatedVersion: "2.0.1",
            CanUpdate: true,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: [{
              Name: "Nuke.Common",
              Version: "2.0.1",
              Type: "Unknown",
              EvaluationResult: nil,
              TargetFrameworks: ["net462", "netstandard1.6"],
              IsDevDependency: false,
              IsDirect: true,
              IsTransitive: false,
              IsOverride: false,
              IsUpdate: false,
              InfoUrl: nil
            }]
          }
        )
      end

      it "reports the expected result" do
        run_analyze_test do |checker|
          expect(checker.up_to_date?).to be(false)
        end
      end
    end

    context "with a private source authentication failure" do
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_requirements) { [] }
      let(:dependency_version) { "2.0.0" }

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: false,
            Projects: [],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Nuke.Common",
          analysis_content_hash: {
            UpdatedVersion: "",
            CanUpdate: false,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: [],
            ErrorType: "AuthenticationFailure",
            ErrorDetails: "the-error-details"
          }
        )
      end

      it "raises the correct error" do
        run_analyze_test do |checker|
          expect { checker.up_to_date? }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
        end
      end
    end
  end

  describe "#latest_resolvable_version" do
    context "when a partial unlock cannot be performed" do
      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [
              {
                FilePath: "my.csproj",
                Dependencies: [{
                  Name: "Microsoft.Extensions.DependencyModel",
                  Version: "1.1.1",
                  Type: "Unknown",
                  EvaluationResult: nil,
                  TargetFrameworks: ["net8.0"],
                  IsDevDependency: false,
                  IsDirect: true,
                  IsTransitive: false,
                  IsOverride: false,
                  IsUpdate: false,
                  InfoUrl: nil
                }],
                IsSuccess: true,
                Properties: [
                  {
                    Name: "TargetFramework",
                    Value: "net8.0",
                    SourceFilePath: "my.csproj"
                  }
                ],
                TargetFrameworks: ["net8.0"],
                ReferencedProjectPaths: []
              }
            ],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Microsoft.Extensions.DependencyModel",
          analysis_content_hash: {
            UpdatedVersion: "1.1.2",
            CanUpdate: true,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: [{
              Name: "Microsoft.Extensions.DependencyModel",
              Version: "1.1.2",
              Type: "Unknown",
              EvaluationResult: nil,
              TargetFrameworks: ["net8.0"],
              IsDevDependency: false,
              IsDirect: true,
              IsTransitive: false,
              IsOverride: false,
              IsUpdate: false,
              InfoUrl: nil
            }]
          }
        )
      end

      it "reports `nil`" do
        run_analyze_test do |checker|
          expect(checker.latest_resolvable_version).to be_nil
        end
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    context "when a full unlock cannot be performed" do
      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [
              {
                FilePath: "my.csproj",
                Dependencies: [{
                  Name: "Microsoft.Extensions.DependencyModel",
                  Version: "1.1.1",
                  Type: "Unknown",
                  EvaluationResult: nil,
                  TargetFrameworks: ["net8.0"],
                  IsDevDependency: false,
                  IsDirect: true,
                  IsTransitive: false,
                  IsOverride: false,
                  IsUpdate: false,
                  InfoUrl: nil
                }],
                IsSuccess: true,
                Properties: [
                  {
                    Name: "TargetFramework",
                    Value: "net8.0",
                    SourceFilePath: "my.csproj"
                  }
                ],
                TargetFrameworks: ["net8.0"],
                ReferencedProjectPaths: []
              }
            ],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Microsoft.Extensions.DependencyModel",
          analysis_content_hash: {
            UpdatedVersion: "1.1.2",
            CanUpdate: true,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: [{
              Name: "Microsoft.Extensions.DependencyModel",
              Version: "1.1.2",
              Type: "Unknown",
              EvaluationResult: nil,
              TargetFrameworks: ["net8.0"],
              IsDevDependency: false,
              IsDirect: true,
              IsTransitive: false,
              IsOverride: false,
              IsUpdate: false,
              InfoUrl: nil
            }]
          }
        )
      end

      it "returns `nil`" do
        run_analyze_test do |checker|
          expect(checker.latest_resolvable_version_with_no_unlock).to be_nil
        end
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    context "when there is a newer package available" do
      let(:dependency_requirements) do
        [{
          requirement: "0.1.434",
          file: "my.csproj",
          groups: ["dependencies"],
          source: nil,
          metadata: { property_name: "NukeVersion" }
        }]
      end
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_version) { "0.1.434" }

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [
              {
                FilePath: "my.csproj",
                Dependencies: [{
                  Name: "Nuke.Common",
                  Version: "0.1.434",
                  Type: "PackageReference",
                  EvaluationResult: nil,
                  TargetFrameworks: ["net8.0"],
                  IsDevDependency: false,
                  IsDirect: true,
                  IsTransitive: false,
                  IsOverride: false,
                  IsUpdate: false,
                  InfoUrl: nil
                }],
                IsSuccess: true,
                Properties: [
                  {
                    Name: "TargetFramework",
                    Value: "net8.0",
                    SourceFilePath: "my.csproj"
                  }
                ],
                TargetFrameworks: ["net8.0"],
                ReferencedProjectPaths: []
              }
            ],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Nuke.Common",
          analysis_content_hash: {
            UpdatedVersion: "6.3.0",
            CanUpdate: true,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: [{
              Name: "Nuke.Common",
              Version: "6.3.0",
              Type: "Unknown",
              EvaluationResult: nil,
              TargetFrameworks: ["net8.0"],
              IsDevDependency: false,
              IsDirect: true,
              IsTransitive: false,
              IsOverride: false,
              IsUpdate: false,
              InfoUrl: nil
            }]
          }
        )
      end

      it "reports the expected result" do
        run_analyze_test do |checker|
          expect(checker.requirements_unlocked_or_can_be?).to be(true)
        end
      end
    end
  end

  describe "#lowest_security_fix_version" do
    context "when an appropriate version is returned" do
      let(:target_version) { "2.0.0" }
      let(:vulnerable_versions) { ["< 2.0.0"] }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "nuget",
            vulnerable_versions: vulnerable_versions
          )
        ]
      end

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [
              {
                FilePath: "my.csproj",
                Dependencies: [{
                  Name: "Microsoft.Extensions.DependencyModel",
                  Version: "1.1.1",
                  Type: "PackageReference",
                  EvaluationResult: nil,
                  TargetFrameworks: ["net8.0"],
                  IsDevDependency: false,
                  IsDirect: true,
                  IsTransitive: false,
                  IsOverride: false,
                  IsUpdate: false,
                  InfoUrl: nil
                }],
                IsSuccess: true,
                Properties: [
                  {
                    Name: "TargetFramework",
                    Value: "net8.0",
                    SourceFilePath: "my.csproj"
                  }
                ],
                TargetFrameworks: ["net8.0"],
                ReferencedProjectPaths: []
              }
            ],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Microsoft.Extensions.DependencyModel",
          analysis_content_hash: {
            UpdatedVersion: "2.0.0",
            CanUpdate: true,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: [{
              Name: "Microsoft.Extensions.DependencyModel",
              Version: "2.0.0",
              Type: "Unknown",
              EvaluationResult: nil,
              TargetFrameworks: ["net8.0"],
              IsDevDependency: false,
              IsDirect: true,
              IsTransitive: false,
              IsOverride: false,
              IsUpdate: false,
              InfoUrl: nil
            }]
          }
        )
      end

      it "reports the expected result" do
        run_analyze_test do |checker|
          expect(checker.lowest_security_fix_version).to eq(target_version)
        end
      end
    end

    context "when the security vulnerability excludes all compatible packages" do
      let(:target_version) { "1.1.1" }
      let(:vulnerable_versions) { ["< 999.999.999"] } # it's all bad
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "nuget",
            vulnerable_versions: vulnerable_versions
          )
        ]
      end

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [
              {
                FilePath: "my.csproj",
                Dependencies: [{
                  Name: "Microsoft.Extensions.DependencyModel",
                  Version: "1.1.1",
                  Type: "PackageReference",
                  EvaluationResult: nil,
                  TargetFrameworks: ["net8.0"],
                  IsDevDependency: false,
                  IsDirect: true,
                  IsTransitive: false,
                  IsOverride: false,
                  IsUpdate: false,
                  InfoUrl: nil
                }],
                IsSuccess: true,
                Properties: [
                  {
                    Name: "TargetFramework",
                    Value: "net8.0",
                    SourceFilePath: "my.csproj"
                  }
                ],
                TargetFrameworks: ["net8.0"],
                ReferencedProjectPaths: []
              }
            ],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Microsoft.Extensions.DependencyModel",
          analysis_content_hash: {
            UpdatedVersion: "1.1.1",
            CanUpdate: false,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: []
          }
        )
      end

      it "reports the expected result" do
        run_analyze_test do |checker|
          expect(checker.lowest_security_fix_version).to eq(target_version)
        end
      end
    end
  end

  describe "#updated_dependencies(requirements_to_unlock: :all)" do
    context "when all dependencies can update to the latest version" do
      let(:dependency_requirements) do
        [{
          requirement: "0.1.434",
          file: "my.csproj",
          groups: ["dependencies"],
          source: nil,
          metadata: { property_name: "NukeVersion" }
        }]
      end
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_version) { "0.1.434" }

      before do
        intercept_native_tools(
          discovery_content_hash: {
            Path: "",
            IsSuccess: true,
            Projects: [
              {
                FilePath: "my.csproj",
                Dependencies: [{
                  Name: "Nuke.CodeGeneration",
                  Version: "0.1.434",
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
                  Name: "Nuke.Common",
                  Version: "0.1.434",
                  Type: "PackageReference",
                  EvaluationResult: nil,
                  TargetFrameworks: ["net8.0"],
                  IsDevDependency: false,
                  IsDirect: true,
                  IsTransitive: false,
                  IsOverride: false,
                  IsUpdate: false,
                  InfoUrl: nil
                }],
                IsSuccess: true,
                Properties: [
                  {
                    Name: "TargetFramework",
                    Value: "net8.0",
                    SourceFilePath: "my.csproj"
                  }
                ],
                TargetFrameworks: ["net8.0"],
                ReferencedProjectPaths: []
              }
            ],
            DirectoryPackagesProps: nil,
            GlobalJson: nil,
            DotNetToolsJson: nil
          },
          dependency_name: "Nuke.Common",
          analysis_content_hash: {
            UpdatedVersion: "6.3.0",
            CanUpdate: true,
            VersionComesFromMultiDependencyProperty: false,
            UpdatedDependencies: [{
              Name: "Nuke.CodeGeneration",
              Version: "6.3.0",
              Type: "Unknown",
              EvaluationResult: nil,
              TargetFrameworks: ["net8.0"],
              IsDevDependency: false,
              IsDirect: true,
              IsTransitive: false,
              IsOverride: false,
              IsUpdate: false,
              InfoUrl: "https://nuget.example.com/nuke.codegeneration"
            }, {
              Name: "Nuke.Common",
              Version: "6.3.0",
              Type: "Unknown",
              EvaluationResult: nil,
              TargetFrameworks: ["net8.0"],
              IsDevDependency: false,
              IsDirect: true,
              IsTransitive: false,
              IsOverride: false,
              IsUpdate: false,
              InfoUrl: "https://nuget.example.com/nuke.common"
            }]
          }
        )
      end

      it "reports the expected result" do
        run_analyze_test do |checker|
          expect(checker.updated_dependencies(requirements_to_unlock: :all)).to eq([
            Dependabot::Dependency.new(
              name: "Nuke.CodeGeneration",
              version: "6.3.0",
              previous_version: "0.1.434",
              requirements: [{
                requirement: "6.3.0",
                file: "/my.csproj",
                groups: ["dependencies"],
                source: {
                  type: "nuget_repo",
                  source_url: "https://nuget.example.com/nuke.codegeneration"
                }
              }],
              previous_requirements: [{
                requirement: "0.1.434",
                file: "/my.csproj",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "nuget"
            ),
            Dependabot::Dependency.new(
              name: "Nuke.Common",
              version: "6.3.0",
              previous_version: "0.1.434",
              requirements: [{
                requirement: "6.3.0",
                file: "/my.csproj",
                groups: ["dependencies"],
                source: {
                  type: "nuget_repo",
                  source_url: "https://nuget.example.com/nuke.common"
                }
              }],
              previous_requirements: [{
                requirement: "0.1.434",
                file: "/my.csproj",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "nuget"
            )
          ])
        end
      end
    end
  end
end
