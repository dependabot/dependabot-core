# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/nuget/cache_manager"
require "dependabot/nuget/file_parser/project_file_parser"
require_relative "../nuget_search_stubs"

RSpec.describe Dependabot::Nuget::FileParser::ProjectFileParser do
  RSpec.configure do |config|
    config.include(NuGetSearchStubs)
  end

  let(:file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
  end
  let(:file_body) { fixture("csproj", "basic.csproj") }
  let(:parser) do
    described_class.new(dependency_files: [file], credentials: credentials, repo_contents_path: "/test/repo")
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before do
    # these search results are used by many tests; for these tests, the actual versions don't matter, it just matters
    # that search returns _something_
    versions = ["2.2.2", "1.1.1", "1.0.0"]
    stub_search_results_with_versions_v3("gitversion.commandline", versions)
    stub_search_results_with_versions_v3("microsoft.aspnetcore.app", versions)
    stub_search_results_with_versions_v3("microsoft.extensions.dependencymodel", versions)
    stub_search_results_with_versions_v3("microsoft.extensions.platformabstractions", versions)
    stub_search_results_with_versions_v3("microsoft.net.test.sdk", versions)
    stub_search_results_with_versions_v3("microsoft.sourcelink.github", versions)
    stub_search_results_with_versions_v3("newtonsoft.json", versions)
    stub_search_results_with_versions_v3("nanoframework.corelibrary", versions)
    stub_search_results_with_versions_v3("nuke.codegeneration", versions)
    stub_search_results_with_versions_v3("nuke.common", versions)
    stub_search_results_with_versions_v3("serilog", versions)
    stub_search_results_with_versions_v3("system.collections.specialized", versions)
  end

  describe "#downstream_file_references" do
    subject(:downstream_file_references) { parser.downstream_file_references(project_file: file) }

    context "when there is no `Include` or `Update` attribute on the `<PackageReference>`" do
      let(:file_body) do
        <<~XML
          <Project Sdk="Microsoft.NET.Sdk">
            <PropertyGroup>
              <TargetFramework>net8.0</TargetFramework>
            </PropertyGroup>
            <ItemGroup>
              <ProjectReference Exclude="Not.Used.Here.csproj" />
              <ProjectReference Include="Some.Other.Project.csproj" />
            </ItemGroup>
          </Project>
        XML
      end

      it "does not report that dependency" do
        expect(downstream_file_references).to eq(Set["Some.Other.Project.csproj"])
      end
    end
  end

  describe "dependency_set" do
    subject(:dependency_set) { parser.dependency_set(project_file: file) }

    before do
      allow(parser).to receive(:transitive_dependencies_from_packages).and_return([])
    end

    it { is_expected.to be_a(Dependabot::FileParsers::Base::DependencySet) }

    describe "the transitive dependencies" do
      let(:file_body) { fixture("csproj", "transitive_project_reference.csproj") }
      let(:file) do
        Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
      end
      let(:files) do
        [
          file,
          Dependabot::DependencyFile.new(
            name: "ref/another.csproj",
            content: fixture("csproj", "transitive_referenced_project.csproj")
          )
        ]
      end
      let(:parser) do
        described_class.new(dependency_files: files, credentials: credentials, repo_contents_path: "/test/repo")
      end
      let(:dependencies) { dependency_set.dependencies }
      subject(:transitive_dependencies) { dependencies.reject(&:top_level?) }

      its(:length) { is_expected.to eq(20) }

      def dependencies_from(dep_info)
        dep_info.map do |info|
          Dependabot::Dependency.new(
            name: info[:name],
            version: info[:version],
            requirements: [],
            package_manager: "nuget"
          )
        end
      end

      let(:raw_transitive_dependencies) do
        [
          { name: "Microsoft.CSharp", version: "4.0.1" },
          { name: "System.Dynamic.Runtime", version: "4.0.11" },
          { name: "System.Linq.Expressions", version: "4.1.0" },
          { name: "System.Reflection", version: "4.1.0" },
          { name: "Microsoft.NETCore.Platforms", version: "1.0.1" },
          { name: "Microsoft.NETCore.Targets", version: "1.0.1" },
          { name: "System.IO", version: "4.1.0" },
          { name: "System.Runtime", version: "4.1.0" },
          { name: "System.Text.Encoding", version: "4.0.11" },
          { name: "System.Threading.Tasks", version: "4.0.11" },
          { name: "System.Reflection.Primitives", version: "4.0.1" },
          { name: "System.ObjectModel", version: "4.0.12" },
          { name: "System.Collections", version: "4.0.11" },
          { name: "System.Globalization", version: "4.0.11" },
          { name: "System.Linq", version: "4.1.0" },
          { name: "System.Reflection.Extensions", version: "4.0.1" },
          { name: "System.Runtime.Extensions", version: "4.1.0" },
          { name: "System.Text.RegularExpressions", version: "4.1.0" },
          { name: "System.Threading", version: "4.0.11" }
        ]
      end

      before do
        allow(parser).to receive(:transitive_dependencies_from_packages).and_return(
          dependencies_from(raw_transitive_dependencies)
        )
      end

      describe "the referenced project dependencies" do
        subject(:dependency) do
          transitive_dependencies.find do |dep|
            dep.name == "Microsoft.Extensions.DependencyModel"
          end
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Extensions.DependencyModel")
          expect(dependency.version).to eq("1.0.1")
          expect(dependency.requirements).to eq([])
        end
      end
    end

    describe "dependencies from Directory.Packages.props" do
      let(:parser) do
        described_class.new(dependency_files: dependency_files, credentials: credentials,
                            repo_contents_path: "/test/repo")
      end
      let(:project_file) do
        Dependabot::DependencyFile.new(
          name: "project.csproj",
          content:
            <<~XML
              <Project Sdk="Microsoft.NET.Sdk">
                <PropertyGroup>
                  <TargetFramework>net8.0</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                  <PackageReference Include="Some.Package" />
                  <PackageReference Include="Some.Other.Package" />
                </ItemGroup>
              </Project>
            XML
        )
      end
      let(:dependency_set) { parser.dependency_set(project_file: project_file) }
      let(:dependency_files) do
        [
          project_file,
          Dependabot::DependencyFile.new(
            name: "Directory.Packages.props",
            content:
              <<~XML
                <Project>
                  <PropertyGroup>
                    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageVersion Include="Some.Package" Version="$(SomePropertyThatIsNotResolvable)" />
                    <PackageVersion Include="Some.Other.Package" Version="4.5.6" />
                  </ItemGroup>
                </Project>
              XML
          )
        ]
      end

      subject(:dependencies) { dependency_set.dependencies }

      before do
        stub_search_results_with_versions_v3("some.package", ["1.2.3"])
        stub_search_results_with_versions_v3("some.other.package", ["4.5.6"])
      end

      it "returns the correct information" do
        expect(dependencies.length).to eq(2)

        expect(dependencies[0]).to be_a(Dependabot::Dependency)
        expect(dependencies[0].name).to eq("Some.Package")
        expect(dependencies[0].version).to eq("$SomePropertyThatIsNotResolvable")

        expect(dependencies[1]).to be_a(Dependabot::Dependency)
        expect(dependencies[1].name).to eq("Some.Other.Package")
        expect(dependencies[1].version).to eq("4.5.6")
      end
    end

    describe "the top_level dependencies" do
      let(:dependencies) { dependency_set.dependencies }
      subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

      its(:length) { is_expected.to eq(5) }

      before do
        stub_search_results_with_versions_v3("system.askjeeves", ["1.0.0", "1.1.0"])
        stub_search_results_with_versions_v3("system.google", ["1.0.0", "1.1.0"])
        stub_search_results_with_versions_v3("system.lycos", ["1.0.0", "1.1.0"])
        stub_search_results_with_versions_v3("system.webcrawler", ["1.0.0", "1.1.0"])
      end

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

      describe "the second dependency" do
        subject(:dependency) { top_level_dependencies[1] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.AspNetCore.App")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: nil,
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

      context "with version ranges" do
        let(:file_body) { fixture("csproj", "ranges.csproj") }

        its(:length) { is_expected.to eq(6) }

        before do
          stub_search_results_with_versions_v3("dep1", ["1.1.0", "1.2.0"])
          stub_search_results_with_versions_v3("dep2", ["1.1.0", "1.2.0"])
          stub_search_results_with_versions_v3("dep3", ["0.9.0", "1.0.0"])
          stub_search_results_with_versions_v3("dep4", ["1.0.0", "1.0.1"])
          stub_search_results_with_versions_v3("dep5", ["1.1.0", "1.2.0"])
          stub_search_results_with_versions_v3("dep6", ["1.1.0", "1.2.0"])
        end

        it "has the right details" do
          expect(top_level_dependencies.first.requirements.first.fetch(:requirement))
            .to eq("[1.0,2.0]")
          expect(top_level_dependencies.first.version).to be_nil

          expect(top_level_dependencies[1].requirements.first.fetch(:requirement))
            .to eq("[1.1]")
          expect(top_level_dependencies[1].version).to eq("1.1")

          expect(top_level_dependencies[2].requirements.first.fetch(:requirement))
            .to eq("(,1.0)")
          expect(top_level_dependencies[2].version).to be_nil

          expect(top_level_dependencies[3].requirements.first.fetch(:requirement))
            .to eq("1.0.*")
          expect(top_level_dependencies[3].version).to be_nil

          expect(top_level_dependencies[4].requirements.first.fetch(:requirement))
            .to eq("*")
          expect(top_level_dependencies[4].version).to be_nil

          expect(top_level_dependencies[5].requirements.first.fetch(:requirement))
            .to eq("*-*")
          expect(top_level_dependencies[5].version).to be_nil
        end
      end

      context "with an update specified" do
        let(:file_body) { fixture("csproj", "update.csproj") }

        it "has the right details" do
          expect(top_level_dependencies.map(&:name))
            .to match_array(
              %w(
                Microsoft.Extensions.DependencyModel
                Microsoft.AspNetCore.App
                Microsoft.Extensions.PlatformAbstractions
                System.Collections.Specialized
              )
            )
        end
      end

      context "with an updated package specified" do
        let(:file_body) { fixture("csproj", "packages.props") }

        it "has the right details" do
          expect(top_level_dependencies.map(&:name))
            .to match_array(
              %w(
                Microsoft.SourceLink.GitHub
                System.AskJeeves
                System.Google
                System.Lycos
                System.WebCrawler
              )
            )
        end
      end

      context "with an updated package specified" do
        let(:file_body) { fixture("csproj", "directory.packages.props") }

        it "has the right details" do
          expect(top_level_dependencies.map(&:name))
            .to match_array(
              %w(
                System.AskJeeves
                System.Google
                System.Lycos
                System.WebCrawler
              )
            )
        end
      end

      context "with a property version" do
        let(:file_body) do
          fixture("csproj", "property_version.csproj")
        end

        describe "the property dependency" do
          subject(:dependency) do
            top_level_dependencies.find { |d| d.name == "Nuke.Common" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("Nuke.Common")
            expect(dependency.version).to eq("0.1.434")
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.1.434",
                file: "my.csproj",
                groups: ["dependencies"],
                source: nil,
                metadata: { property_name: "NukeVersion" }
              }]
            )
          end
        end

        context "that is indirect" do
          let(:file_body) do
            fixture("csproj", "property_version_indirect.csproj")
          end

          subject(:dependency) do
            top_level_dependencies.find { |d| d.name == "Nuke.Uncommon" }
          end

          before do
            stub_search_results_with_versions_v3("nuke.uncommon", ["0.1.434"])
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("Nuke.Uncommon")
            expect(dependency.version).to eq("0.1.434")
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.1.434",
                file: "my.csproj",
                groups: ["dependencies"],
                source: nil,
                metadata: { property_name: "NukeVersion" }
              }]
            )
          end
        end

        context "from a Directory.Build.props file several directories up" do
          # src/my.csproj
          let(:file_body) do
            fixture("csproj", "property_version_not_in_file.csproj")
          end
          let(:file) do
            Dependabot::DependencyFile.new(name: "src/my.csproj", content: file_body)
          end

          # src/Directory.Build.props
          let(:directory_build_props) do
            Dependabot::DependencyFile.new(name: "src/Directory.Build.props",
                                           content: fixture("csproj",
                                                            "directory_build_props_that_pulls_in_from_parent.props"))
          end

          # Directory.Build.props
          let(:root_directory_build_props) do
            Dependabot::DependencyFile.new(name: "Directory.Build.props",
                                           content: fixture("csproj",
                                                            "directory_build_props_with_property_version.props"))
          end

          let(:files) do
            [
              file,
              directory_build_props,
              root_directory_build_props
            ]
          end

          let(:parser) do
            described_class.new(dependency_files: files, credentials: credentials,
                                repo_contents_path: "/test/repo")
          end

          subject(:dependency) do
            top_level_dependencies.find { |d| d.name == "Newtonsoft.Json" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("Newtonsoft.Json")
            expect(dependency.version).to eq("9.0.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "9.0.1",
                file: "src/my.csproj",
                groups: ["dependencies"],
                source: nil,
                metadata: { property_name: "NewtonsoftJsonVersion" }
              }]
            )
          end
        end

        context "from a Directory.Build.targets file several directories up" do
          # src/my.csproj
          let(:file_body) do
            fixture("csproj", "property_version_not_in_file.csproj")
          end
          let(:file) do
            Dependabot::DependencyFile.new(name: "src/my.csproj", content: file_body)
          end

          # src/Directory.Build.targets
          let(:directory_build_props) do
            Dependabot::DependencyFile.new(name: "src/Directory.Build.targets",
                                           content: fixture("csproj",
                                                            "directory_build_props_that_pulls_in_from_parent.props"))
          end

          # Directory.Build.targets
          let(:root_directory_build_props) do
            Dependabot::DependencyFile.new(name: "Directory.Build.targets",
                                           content: fixture("csproj",
                                                            "directory_build_props_with_property_version.props"))
          end

          let(:files) do
            [
              file,
              directory_build_props,
              root_directory_build_props
            ]
          end

          let(:parser) do
            described_class.new(dependency_files: files, credentials: credentials,
                                repo_contents_path: "/test/repo")
          end

          subject(:dependency) do
            top_level_dependencies.find { |d| d.name == "Newtonsoft.Json" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("Newtonsoft.Json")
            expect(dependency.version).to eq("9.0.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "9.0.1",
                file: "src/my.csproj",
                groups: ["dependencies"],
                source: nil,
                metadata: { property_name: "NewtonsoftJsonVersion" }
              }]
            )
          end
        end

        context "from Directory.Build.props with an explicit update in Directory.Build.targets" do
          # src/my.csproj
          let(:file_body) do
            fixture("csproj", "property_version_not_in_file.csproj")
          end
          let(:file) do
            Dependabot::DependencyFile.new(name: "src/my.csproj", content: file_body)
          end

          # src/Directory.Build.props
          let(:directory_build_props) do
            Dependabot::DependencyFile.new(name: "src/Directory.Build.props",
                                           content: fixture("csproj",
                                                            "directory_build_props_that_pulls_in_from_parent.props"))
          end

          # Directory.Build.props
          let(:root_directory_build_props) do
            Dependabot::DependencyFile.new(name: "Directory.Build.props",
                                           content: fixture("csproj",
                                                            "directory_build_props_with_property_version.props"))
          end

          # Directory.Build.targets
          let(:root_directory_build_targets) do
            Dependabot::DependencyFile.new(name: "Directory.Build.targets",
                                           content: fixture("csproj",
                                                            "directory_build_props_with_package_update_variable.props"))
          end

          let(:files) do
            [
              file,
              directory_build_props,
              root_directory_build_props,
              root_directory_build_targets
            ]
          end

          let(:parser) do
            described_class.new(dependency_files: files, credentials: credentials,
                                repo_contents_path: "/test/repo")
          end

          subject(:dependency) do
            top_level_dependencies.find { |d| d.name == "Newtonsoft.Json" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("Newtonsoft.Json")
            expect(dependency.version).to eq("9.0.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "9.0.1",
                file: "src/my.csproj",
                groups: ["dependencies"],
                source: nil,
                metadata: { property_name: "NewtonsoftJsonVersion" }
              },
               {
                 requirement: "9.0.1",
                 file: "Directory.Build.targets",
                 groups: ["dependencies"],
                 source: nil,
                 metadata: { property_name: "NewtonsoftJsonVersion" }
               }]
            )
          end
        end

        context "that can't be found" do
          let(:file_body) do
            fixture("csproj", "missing_property_version.csproj")
          end

          describe "the property dependency" do
            subject(:dependency) do
              top_level_dependencies.find { |d| d.name == "Nuke.Common" }
            end

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("Nuke.Common")
              expect(dependency.version).to eq("$UnknownVersion")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "$(UnknownVersion)",
                  file: "my.csproj",
                  groups: ["dependencies"],
                  source: nil,
                  metadata: { property_name: "UnknownVersion" }
                }]
              )
            end
          end

          describe "the dependency name" do
            let(:file_body) do
              fixture("csproj", "dependency_with_name_that_does_not_exist.csproj")
            end

            before do
              stub_no_search_results("this.dependency.does.not.exist")
            end

            it "has the right details" do
              expect(top_level_dependencies.count).to eq(1)
              expect(top_level_dependencies.first).to be_a(Dependabot::Dependency)
              expect(top_level_dependencies.first.name).to eq("Microsoft.Extensions.DependencyModel")
              expect(top_level_dependencies.first.version).to eq("1.1.1")
              expect(top_level_dependencies.first.requirements).to eq(
                [{
                  requirement: "1.1.1",
                  file: "my.csproj",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          # This is a bit of a noop now that we're moved off the query Nuget API,
          # But we're keeping the test for completeness.
          describe "the dependency name is a partial, but not perfect match" do
            let(:file_body) do
              fixture("csproj", "dependency_with_name_that_does_not_exist.csproj")
            end

            before do
              stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/this.dependency.does.not.exist/index.json")
                .to_return(status: 404, body: "")

              stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/this.dependency.does.not.exist_but.this.one.does")
                .to_return(status: 200, body: registration_results(
                  "this.dependency.does.not.exist_but.this.one.does", ["1.0.0"]
                ))
            end

            it "has the right details" do
              expect(top_level_dependencies.count).to eq(1)
              expect(top_level_dependencies.first).to be_a(Dependabot::Dependency)
              expect(top_level_dependencies.first.name).to eq("Microsoft.Extensions.DependencyModel")
              expect(top_level_dependencies.first.version).to eq("1.1.1")
              expect(top_level_dependencies.first.requirements).to eq(
                [{
                  requirement: "1.1.1",
                  file: "my.csproj",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          describe "using non-standard nuget sources" do
            let(:file_body) do
              fixture("csproj", "dependency_with_name_that_does_not_exist.csproj")
            end
            let(:file) do
              Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
            end
            let(:nuget_config_body) do
              <<~XML
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="repo-with-no-results" value="https://no-results.api.example.com/v3/index.json" />
                    <add key="repo-with-results" value="https://with-results.api.example.com/v3/index.json" />
                  </packageSources>
                </configuration>
              XML
            end
            let(:nuget_config_file) do
              Dependabot::DependencyFile.new(name: "NuGet.config", content: nuget_config_body)
            end
            let(:parser) do
              described_class.new(dependency_files: [file, nuget_config_file], credentials: credentials,
                                  repo_contents_path: "/test/repo")
            end

            before do
              # no results
              stub_request(:get, "https://no-results.api.example.com/v3/index.json")
                .to_return(status: 200, body: fixture("nuget_responses", "index.json",
                                                      "no-results.api.example.com.index.json"))
              stub_request(:get, "https://no-results.api.example.com/v3/registration5-gz-semver2/this.dependency.does.not.exist/index.json")
                .to_return(status: 404, body: "")
              stub_request(:get, "https://no-results.api.example.com/v3/registration5-gz-semver2/microsoft.extensions.dependencymodel/index.json")
                .to_return(status: 404, body: "")

              # with results
              stub_request(:get, "https://with-results.api.example.com/v3/index.json")
                .to_return(status: 200, body: fixture("nuget_responses", "index.json",
                                                      "with-results.api.example.com.index.json"))
              stub_request(:get, "https://with-results.api.example.com/v3/registration5-gz-semver2/" \
                                 "microsoft.extensions.dependencymodel/index.json")
                .to_return(status: 200, body: registration_results("microsoft.extensions.dependencymodel",
                                                                   ["1.1.1", "1.1.0"]))
              stub_request(:get, "https://with-results.api.example.com/v3/registration5-gz-semver2/" \
                                 "this.dependency.does.not.exist/index.json")
                .to_return(status: 404, body: "")
            end

            it "has the right details" do
              expect(top_level_dependencies.count).to eq(1)
              expect(top_level_dependencies.first).to be_a(Dependabot::Dependency)
              expect(top_level_dependencies.first.name).to eq("Microsoft.Extensions.DependencyModel")
              expect(top_level_dependencies.first.version).to eq("1.1.1")
              expect(top_level_dependencies.first.requirements).to eq(
                [{
                  requirement: "1.1.1",
                  file: "my.csproj",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          describe "v2 apis can be queried" do
            let(:file_body) do
              <<~XML
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net7.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.DependencyModel" Version="1.1.1" />
                  </ItemGroup>
                </Project>
              XML
            end
            let(:file) do
              Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
            end
            let(:nuget_config_body) do
              <<~XML
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="nuget.org" value="https://www.nuget.org/api/v2/" />
                  </packageSources>
                </configuration>
              XML
            end
            let(:nuget_config_file) do
              Dependabot::DependencyFile.new(name: "NuGet.config", content: nuget_config_body)
            end
            let(:parser) do
              described_class.new(dependency_files: [file, nuget_config_file], credentials: credentials,
                                  repo_contents_path: "/test/repo")
            end

            before do
              stub_request(:get, "https://www.nuget.org/api/v2/")
                .to_return(status: 200, body: fixture("nuget_responses", "v2_base.xml"))
              stub_request(:get, "https://www.nuget.org/api/v2/FindPackagesById()?id=%27Microsoft.Extensions.DependencyModel%27")
                .to_return(status: 200, body: search_results_with_versions_v2("microsoft.extensions.dependencymodel",
                                                                              ["1.1.1", "1.1.0"]))
            end

            it "has the right details" do
              expect(top_level_dependencies.count).to eq(1)
              expect(top_level_dependencies.first).to be_a(Dependabot::Dependency)
              expect(top_level_dependencies.first.name).to eq("Microsoft.Extensions.DependencyModel")
              expect(top_level_dependencies.first.version).to eq("1.1.1")
              expect(top_level_dependencies.first.requirements).to eq(
                [{
                  requirement: "1.1.1",
                  file: "my.csproj",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          describe "nuget.config files further up the tree are considered" do
            let(:file_body) { "not relevant" }
            let(:file) do
              Dependabot::DependencyFile.new(directory: "src/project", name: "my.csproj", content: file_body)
            end
            let(:nuget_config_body) { "not relevant" }
            let(:nuget_config_file) do
              Dependabot::DependencyFile.new(name: "../../NuGet.Config", content: nuget_config_body)
            end
            let(:parser) do
              described_class.new(dependency_files: [file, nuget_config_file], credentials: credentials,
                                  repo_contents_path: "/test/repo")
            end

            it "finds the config file up several directories" do
              nuget_configs = parser.nuget_configs
              expect(nuget_configs.count).to eq(1)
              expect(nuget_configs.first).to be_a(Dependabot::DependencyFile)
              expect(nuget_configs.first.name).to eq("../../NuGet.Config")
            end
          end

          describe "files with a `nuget.config` suffix are not considered" do
            let(:file_body) { "not relevant" }
            let(:file) do
              Dependabot::DependencyFile.new(directory: "src/project", name: "my.csproj", content: file_body)
            end
            let(:nuget_config_body) { "not relevant" }
            let(:nuget_config_file) do
              Dependabot::DependencyFile.new(name: "../../not-NuGet.Config", content: nuget_config_body)
            end
            let(:parser) do
              described_class.new(dependency_files: [file, nuget_config_file], credentials: credentials,
                                  repo_contents_path: "/test/repo")
            end

            it "does not return a name with a partial match" do
              nuget_configs = parser.nuget_configs
              expect(nuget_configs.count).to eq(0)
            end
          end

          describe "multiple dependencies, but each search URI is only hit once" do
            let(:file_body) do
              <<~XML
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net7.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.DependencyModel_cached" Version="1.1.1" />
                    <ProjectReference Include="my2.csproj" />
                  </ItemGroup>
                </Project>
              XML
            end
            let(:file) do
              Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
            end
            let(:file_2_body) do
              <<~XML
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net7.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.DependencyModel_cached" Version="1.1.1" />
                  </ItemGroup>
                </Project>
              XML
            end
            let(:file2) do
              Dependabot::DependencyFile.new(name: "my2.csproj", content: file_2_body)
            end
            let(:parser) do
              described_class.new(dependency_files: [file, file2], credentials: credentials,
                                  repo_contents_path: "/test/repo")
            end

            before do
              stub_no_search_results("this.dependency.does.not.exist")
              ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "false"
            end

            it "has the right details" do
              ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "false"

              registry_stub = stub_registry_v3("microsoft.extensions.dependencymodel_cached", ["1.1.1", "1.1.0"])

              expect(top_level_dependencies.count).to eq(1)
              expect(top_level_dependencies.first).to be_a(Dependabot::Dependency)
              expect(top_level_dependencies.first.name).to eq("Microsoft.Extensions.DependencyModel_cached")
              expect(top_level_dependencies.first.version).to eq("1.1.1")
              expect(top_level_dependencies.first.requirements).to eq(
                [{
                  requirement: "1.1.1",
                  file: "my.csproj",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
              expect(WebMock::RequestRegistry.instance.times_executed(registry_stub.request_pattern)).to eq(1)
            ensure
              ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "true"
              Dependabot::Nuget::CacheManager.instance_variable_set(:@cache, nil)
            end

            after do
              ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "true"
            end
          end
        end
      end

      context "with a nuproj" do
        let(:file_body) { fixture("csproj", "basic.nuproj") }

        before do
          stub_search_results_with_versions_v3("nanoframework.coreextra", ["1.0.0"])
        end

        it "gets the right number of dependencies" do
          expect(top_level_dependencies.count).to eq(2)
        end

        describe "the first dependency" do
          subject(:dependency) { top_level_dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("nanoFramework.CoreLibrary")
            expect(dependency.version).to eq("1.0.0-preview062")
            expect(dependency.requirements).to eq([{
              requirement: "[1.0.0-preview062]",
              file: "my.csproj",
              groups: ["dependencies"],
              source: nil
            }])
          end
        end

        describe "the second dependency" do
          subject(:dependency) { top_level_dependencies.at(1) }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("nanoFramework.CoreExtra")
            expect(dependency.version).to eq("1.0.0-preview061")
            expect(dependency.requirements).to eq([{
              requirement: "[1.0.0-preview061]",
              file: "my.csproj",
              groups: ["devDependencies"],
              source: nil
            }])
          end
        end
      end

      context "with an interpolated value" do
        let(:file_body) { fixture("csproj", "interpolated.proj") }

        it "excludes the dependencies specified using interpolation" do
          expect(top_level_dependencies.count).to eq(0)
        end
      end

      context "with a versioned sdk reference" do
        before do
          stub_search_results_with_versions_v3("awesome.sdk", ["1.2.3"])
          stub_search_results_with_versions_v3("prototype.sdk", ["1.2.3"])
        end

        context "specified in the Project tag" do
          let(:file_body) { fixture("csproj", "sdk_reference_via_project.csproj") }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("Awesome.Sdk")
              expect(dependency.version).to eq("1.2.3")
              expect(dependency.requirements).to eq([{
                requirement: "1.2.3",
                file: "my.csproj",
                groups: ["dependencies"],
                source: nil
              }])
            end
          end

          describe "the second dependency" do
            subject(:dependency) { top_level_dependencies[1] }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("Prototype.Sdk")
              expect(dependency.version).to eq("0.1.0-beta")
              expect(dependency.requirements).to eq([{
                requirement: "0.1.0-beta",
                file: "my.csproj",
                groups: ["dependencies"],
                source: nil
              }])
            end
          end
        end

        context "specified via an Sdk tag" do
          let(:file_body) { fixture("csproj", "sdk_reference_via_sdk.csproj") }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("Awesome.Sdk")
              expect(dependency.version).to eq("1.2.3")
              expect(dependency.requirements).to eq([{
                requirement: "1.2.3",
                file: "my.csproj",
                groups: ["dependencies"],
                source: nil
              }])
            end
          end

          describe "the second dependency" do
            subject(:dependency) { top_level_dependencies[1] }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("Prototype.Sdk")
              expect(dependency.version).to eq("0.1.0-beta")
              expect(dependency.requirements).to eq([{
                requirement: "0.1.0-beta",
                file: "my.csproj",
                groups: ["dependencies"],
                source: nil
              }])
            end
          end
        end

        context "specified via an Import tag" do
          let(:file_body) { fixture("csproj", "sdk_reference_via_import.csproj") }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("Awesome.Sdk")
              expect(dependency.version).to eq("1.2.3")
              expect(dependency.requirements).to eq([{
                requirement: "1.2.3",
                file: "my.csproj",
                groups: ["dependencies"],
                source: nil
              }])
            end
          end

          describe "the second dependency" do
            subject(:dependency) { top_level_dependencies[1] }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("Prototype.Sdk")
              expect(dependency.version).to eq("0.1.0-beta")
              expect(dependency.requirements).to eq([{
                requirement: "0.1.0-beta",
                file: "my.csproj",
                groups: ["dependencies"],
                source: nil
              }])
            end
          end
        end
      end
    end
  end
end
