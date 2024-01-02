# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/nuget/file_parser/project_file_parser"

module NuGetSearchStubs
  def stub_no_search_results(name)
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?prerelease=true&q=#{name}&semVerLevel=2.0.0")
      .to_return(status: 200, body: fixture("nuget_responses", "search_no_data.json"))
  end

  def stub_search_results_with_versions_v3(name, versions)
    versions_json = {
      "versions": versions
    }.to_json
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/#{name}/index.json")
      .to_return(status: 200, body: versions_json)
    registration_json = registration_results(name, versions)
    stub_request(:get, "https://api.nuget.org/v3/registration5-semver1/#{name}/index.json")
      .to_return(status: 200, body: registration_json)
  end

  def registration_results(name, versions)
    page = {
      "@id": "https://api.nuget.org/v3/registration5-semver1/#{name}/index.json#page/PAGE1",
      "@type": "catalog:CatalogPage",
      "count" => 64,
      "items" => versions.map do |version|
        {
          "catalogEntry" => {
            "@type": "PackageDetails",
            "id" => "#{name}",
            "listed" => true,
            "version" => version
          }
        }
      end
    }
    pages = [page]
    response = {
      "@id": "https://api.nuget.org/v3/registration5-gz-semver1/#{name}/index.json",
      "count" => versions.count,
      "items" => pages
    }
    response.to_json
  end

  def search_results_with_versions_v3(name, versions)
    versions_block = versions.map do |version|
      {
        "version" => version,
        "downloads" => 42,
        "@id" => "https://api.nuget.org/v3/registration5-gz-semver2/#{name}/#{version}.json"
      }
    end
    response = {
      "@context" => {
        "@vocab" => "http://schema.nuget.org/schema#",
        "@base" => "https://api.nuget.org/v3/registration5-gz-semver2/"
      },
      "totalHits" => 1,
      "data" => [
        {
          "@id" => "https://api.nuget.org/v3/registration5-gz-semver2/#{name}/index.json",
          "@type" => "Package",
          "registration" => "https://api.nuget.org/v3/registration5-gz-semver2/#{name}/index.json",
          "id" => name,
          "version" => versions.last,
          "description" => "a description for a package that does not exist",
          "summary" => "a summary for a package that does not exist",
          "title" => "a title for a package that does not exist",
          "totalDownloads" => 42,
          "packageTypes" => [
            {
              "name" => "Dependency"
            }
          ],
          "versions" => versions_block
        }
      ]
    }
    response.to_json
  end

  # rubocop:disable Metrics/MethodLength
  def search_results_with_versions_v2(name, versions)
    entries = versions.map do |version|
      xml = <<~XML
        <entry>
          <id>https://www.nuget.org/api/v2/Packages(Id='#{name}',Version='#{version}')</id>
          <category term="NuGetGallery.OData.V2FeedPackage" scheme="http://schemas.microsoft.com/ado/2007/08/dataservices/scheme" />
          <link rel="edit" href="https://www.nuget.org/api/v2/Packages(Id='#{name}',Version='#{version}')" />
          <link rel="self" href="https://www.nuget.org/api/v2/Packages(Id='#{name}',Version='#{version}')" />
          <title type="text">#{name}</title>
          <updated>2015-07-28T23:37:16Z</updated>
          <author>
              <name>FakeAuthor</name>
          </author>
          <content type="application/zip" src="https://www.nuget.org/api/v2/package/#{name}/#{version}" />
          <m:properties>
            <d:Id>#{name}</d:Id>
            <d:Version>#{version}</d:Version>
            <d:NormalizedVersion>#{version}</d:NormalizedVersion>
            <d:Authors>FakeAuthor</d:Authors>
            <d:Copyright>FakeCopyright</d:Copyright>
            <d:Created m:type="Edm.DateTime">2015-07-28T23:37:16.85+00:00</d:Created>
            <d:Dependencies></d:Dependencies>
            <d:Description>FakeDescription</d:Description>
            <d:DownloadCount m:type="Edm.Int64">42</d:DownloadCount>
            <d:GalleryDetailsUrl>https://www.nuget.org/packages/#{name}/#{version}</d:GalleryDetailsUrl>
            <d:IconUrl m:null="true" />
            <d:IsLatestVersion m:type="Edm.Boolean">false</d:IsLatestVersion>
            <d:IsAbsoluteLatestVersion m:type="Edm.Boolean">false</d:IsAbsoluteLatestVersion>
            <d:IsPrerelease m:type="Edm.Boolean">false</d:IsPrerelease>
            <d:Language m:null="true" />
            <d:LastUpdated m:type="Edm.DateTime">2015-07-28T23:37:16.85+00:00</d:LastUpdated>
            <d:Published m:type="Edm.DateTime">2015-07-28T23:37:16.85+00:00</d:Published>
            <d:PackageHash>FakeHash</d:PackageHash>
            <d:PackageHashAlgorithm>SHA512</d:PackageHashAlgorithm>
            <d:PackageSize m:type="Edm.Int64">42</d:PackageSize>
            <d:ProjectUrl>https://example.com/#{name}</d:ProjectUrl>
            <d:ReportAbuseUrl>https://example.com/#{name}</d:ReportAbuseUrl>
            <d:ReleaseNotes m:null="true" />
            <d:RequireLicenseAcceptance m:type="Edm.Boolean">false</d:RequireLicenseAcceptance>
            <d:Summary></d:Summary>
            <d:Tags></d:Tags>
            <d:Title>#{name}</d:Title>
            <d:VersionDownloadCount m:type="Edm.Int64">42</d:VersionDownloadCount>
            <d:MinClientVersion m:null="true" />
            <d:LastEdited m:type="Edm.DateTime">2018-12-08T05:53:10.917+00:00</d:LastEdited>
            <d:LicenseUrl>http://www.apache.org/licenses/LICENSE-2.0</d:LicenseUrl>
            <d:LicenseNames m:null="true" />
            <d:LicenseReportUrl m:null="true" />
          </m:properties>
        </entry>
      XML
      xml = xml.split("\n").map { |line| "  #{line}" }.join("\n")
      xml
    end.join("\n")
    xml = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <feed xml:base="https://www.nuget.org/api/v2" xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices"
        xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns:georss="http://www.georss.org/georss" xmlns:gml="http://www.opengis.net/gml">
        <m:count>#{versions.length}</m:count>
        <id>http://schemas.datacontract.org/2004/07/</id>
        <title />
        <updated>2023-12-05T23:35:30Z</updated>
        <link rel="self" href="https://www.nuget.org/api/v2/Packages" />
        #{entries}
      </feed>
    XML
    xml
  end
  # rubocop:enable Metrics/MethodLength
end

RSpec.describe Dependabot::Nuget::FileParser::ProjectFileParser do
  RSpec.configure do |config|
    config.include(NuGetSearchStubs)
  end

  let(:file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
  end
  let(:file_body) { fixture("csproj", "basic.csproj") }
  let(:parser) { described_class.new(dependency_files: [file], credentials: credentials) }
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
      let(:parser) { described_class.new(dependency_files: files, credentials: credentials) }
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

          let(:parser) { described_class.new(dependency_files: files, credentials: credentials) }

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

          let(:parser) { described_class.new(dependency_files: files, credentials: credentials) }

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

          let(:parser) { described_class.new(dependency_files: files, credentials: credentials) }

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

          describe "the dependency name is a partial, but not perfect match" do
            let(:file_body) do
              fixture("csproj", "dependency_with_name_that_does_not_exist.csproj")
            end

            before do
              stub_request(:get, "https://azuresearch-usnc.nuget.org/query?prerelease=true&q=this.dependency.does.not.exist&semVerLevel=2.0.0")
                .to_return(status: 200, body: search_results_with_versions_v3(
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
            let(:parser) { described_class.new(dependency_files: [file, nuget_config_file], credentials: credentials) }

            before do
              # no results
              stub_request(:get, "https://no-results.api.example.com/v3/index.json")
                .to_return(status: 200, body: fixture("nuget_responses", "index.json",
                                                      "no-results.api.example.com.index.json"))
              stub_request(:get, "https://no-results.api.example.com/query?prerelease=true&q=microsoft.extensions.dependencymodel&semVerLevel=2.0.0")
                .to_return(status: 200, body: fixture("nuget_responses", "search_no_data.json"))
              stub_request(:get, "https://no-results.api.example.com/query?prerelease=true&q=this.dependency.does.not.exist&semVerLevel=2.0.0")
                .to_return(status: 200, body: fixture("nuget_responses", "search_no_data.json"))
              # with results
              stub_request(:get, "https://with-results.api.example.com/v3/index.json")
                .to_return(status: 200, body: fixture("nuget_responses", "index.json",
                                                      "with-results.api.example.com.index.json"))
              stub_request(:get, "https://with-results.api.example.com/query?prerelease=true&q=microsoft.extensions.dependencymodel&semVerLevel=2.0.0")
                .to_return(status: 200, body: search_results_with_versions_v3("microsoft.extensions.dependencymodel",
                                                                              ["1.1.1", "1.1.0"]))
              stub_request(:get, "https://with-results.api.example.com/query?prerelease=true&q=this.dependency.does.not.exist&semVerLevel=2.0.0")
                .to_return(status: 200, body: fixture("nuget_responses", "search_no_data.json"))
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
            let(:parser) { described_class.new(dependency_files: [file, nuget_config_file], credentials: credentials) }

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
            let(:parser) { described_class.new(dependency_files: [file, file2], credentials: credentials) }

            before do
              stub_no_search_results("this.dependency.does.not.exist")
            end

            it "has the right details" do
              query_stub = stub_search_results_with_versions_v3("microsoft.extensions.dependencymodel_cached",
                                                                ["1.1.1", "1.1.0"])
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
              expect(WebMock::RequestRegistry.instance.times_executed(query_stub.request_pattern)).to eq(1)
            end
          end
        end
      end

      context "with a nuproj" do
        let(:file_body) { fixture("csproj", "basic.nuproj") }

        before do
          stub_search_results_with_versions_v3("nanoframework.coreextra", [])
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
