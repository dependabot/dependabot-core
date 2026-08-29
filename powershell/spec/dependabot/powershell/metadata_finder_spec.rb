# typed: false
# frozen_string_literal: true

require "cgi"
require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/powershell/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Powershell::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency_name) { "Pester" }
  let(:dependency_version) { "6.1.0" }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        file: "MyModule.psd1",
        requirement: dependency_version,
        groups: [],
        source: nil
      }],
      package_manager: "powershell"
    )
  end

  let(:mar_tags_url) do
    "https://mcr.microsoft.com/v2/psresource/#{dependency_name.downcase}/tags/list"
  end
  let(:mar_manifest_url) do
    "https://mcr.microsoft.com/v2/psresource/#{dependency_name.downcase}/manifests/#{dependency_version}"
  end
  let(:gallery_packages_url) do
    "https://www.powershellgallery.com/api/v2/FindPackagesById()?id=%27#{CGI.escape(dependency_name)}%27"
  end

  def gallery_entry(version:, project_url:)
    project_url_element =
      if project_url.nil?
        '<d:ProjectUrl m:null="true" />'
      else
        "<d:ProjectUrl>#{CGI.escapeHTML(project_url)}</d:ProjectUrl>"
      end

    <<~XML
      <entry>
        <content type="application/zip"
                 src="https://www.powershellgallery.com/api/v2/package/Pester/#{version}" />
        <m:properties>
          <d:Version>#{version}</d:Version>
          <d:Published>2026-08-11T18:30:55.117</d:Published>
          #{project_url_element}
        </m:properties>
      </entry>
    XML
  end

  def gallery_feed(entries:)
    <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom"
            xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices"
            xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata">
        #{entries.join("\n")}
      </feed>
    XML
  end

  def mar_manifest(metadata)
    JSON.dump(
      "schemaVersion" => 2,
      "mediaType" => "application/vnd.oci.image.manifest.v1+json",
      "layers" => [{
        "mediaType" => "application/vnd.oci.image.layer.v1.tar+gzip",
        "digest" => "sha256:4465339b2c52cb19d0cb6ee16467076cd7f32633e9195df675373eb81e0e8cca",
        "size" => 10_201_874,
        "annotations" => { "metadata" => JSON.dump(metadata) }
      }]
    )
  end

  def stub_gallery(project_url:, version: dependency_version)
    stub_request(:get, mar_tags_url).to_return(status: 404, body: "")
    stub_request(:get, gallery_packages_url).to_return(
      status: 200,
      body: gallery_feed(entries: [gallery_entry(version: version, project_url: project_url)])
    )
  end

  def stub_mar(project_uri:)
    stub_request(:get, mar_tags_url).to_return(
      status: 200,
      body: JSON.dump("name" => "psresource/#{dependency_name.downcase}", "tags" => [dependency_version])
    )
    metadata = {
      "ModuleVersion" => dependency_version,
      "PrivateData" => {
        "PSData" => {
          "ProjectUri" => project_uri,
          "LicenseUri" => "https://aka.ms/azps-license",
          "ReleaseNotes" => "Release notes are text, not necessarily a URL."
        }
      }
    }
    stub_request(:get, mar_manifest_url).to_return(status: 200, body: mar_manifest(metadata))
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when the module is available from Microsoft Artifact Registry" do
      let(:dependency_name) { "Az.Accounts" }
      let(:dependency_version) { "5.5.2" }

      before do
        stub_mar(project_uri: "https://github.com/Azure/azure-powershell")
        stub_request(:get, gallery_packages_url).to_return(
          status: 200,
          body: gallery_feed(
            entries: [
              gallery_entry(
                version: dependency_version,
                project_url: "https://github.com/untrusted/azure-powershell"
              )
            ]
          )
        )
      end

      it "uses project metadata from the selected MAR version and caches it" do
        expect(source_url).to eq("https://github.com/Azure/azure-powershell")
        expect(finder.homepage_url).to eq("https://github.com/Azure/azure-powershell")
        expect(a_request(:get, mar_tags_url)).to have_been_made.once
        expect(a_request(:get, mar_manifest_url)).to have_been_made.once
        expect(a_request(:get, gallery_packages_url)).not_to have_been_made
      end
    end

    context "when Pester is only available from PowerShell Gallery" do
      before do
        stub_gallery(project_url: "  http://github.com/Pester/Pester.git  ")
      end

      it "falls back after the initial MAR 404 and normalizes the GitHub URL" do
        expect(source_url).to eq("https://github.com/Pester/Pester")
        expect(a_request(:get, mar_tags_url)).to have_been_made.once
        expect(a_request(:get, gallery_packages_url)).to have_been_made.once
      end
    end

    context "when PSScriptAnalyzer is only available from PowerShell Gallery" do
      let(:dependency_name) { "PSScriptAnalyzer" }
      let(:dependency_version) { "1.25.0" }

      before do
        stub_gallery(project_url: "https://github.com/PowerShell/PSScriptAnalyzer")
      end

      it "uses the selected Gallery version's project URL" do
        expect(source_url).to eq("https://github.com/PowerShell/PSScriptAnalyzer")
      end
    end

    context "when Gallery metadata identifies a supported non-GitHub repository" do
      let(:dependency_name) { "ADComputerRange" }
      let(:dependency_version) { "0.0.3" }

      before do
        stub_gallery(project_url: "https://gitlab.com/fredericpetit/ad-computer-range/")
      end

      it "delegates supported repository normalization to Dependabot::Source" do
        expect(source_url).to eq("https://gitlab.com/fredericpetit/ad-computer-range")
      end
    end

    context "when Gallery metadata identifies a GitLab subgroup repository" do
      let(:dependency_name) { "SubgroupModule" }
      let(:dependency_version) { "1.0.0" }

      before do
        stub_gallery(project_url: "https://gitlab.com/org/group/repository")
      end

      it "preserves the supported subgroup namespace" do
        expect(source_url).to eq("https://gitlab.com/org/group/repository")
      end
    end

    context "when Gallery metadata identifies an Azure DevOps repository path" do
      let(:dependency_name) { "Get-AzVMDeletionActivity" }
      let(:dependency_version) { "0.6.0" }

      before do
        stub_gallery(
          project_url: " https://dev.azure.com/ayn/PowerShell/_git/AzIaaS?path=%2FGet-AzVMDeletionActivity.ps1"
        )
      end

      it "returns the canonical repository URL without the file query" do
        expect(source_url).to eq("https://dev.azure.com/ayn/PowerShell/_git/AzIaaS")
      end
    end

    context "when Gallery metadata identifies a project-less Azure DevOps repository" do
      let(:dependency_name) { "ProjectlessAzureModule" }
      let(:dependency_version) { "1.0.0" }

      before do
        stub_gallery(project_url: "https://dev.azure.com/greysteil/_git/dependabot-test?path")
      end

      it "preserves the supported project-less repository path" do
        expect(source_url).to eq("https://dev.azure.com/greysteil/_git/dependabot-test")
      end
    end

    {
      "GitHub tree" => [
        "https://github.com/stadub/PowershellScripts/tree/master/7Zip",
        "https://github.com/stadub/PowershellScripts"
      ],
      "GitHub blob" => [
        "https://github.com/organization/repository/blob/main/README.md",
        "https://github.com/organization/repository"
      ],
      "GitLab subgroup blob" => [
        "https://gitlab.com/organization/group/repository/blob/main/README.md",
        "https://gitlab.com/organization/group/repository"
      ],
      "GitLab modern tree" => [
        "https://gitlab.com/organization/repository/-/tree/main/lib",
        "https://gitlab.com/organization/repository"
      ],
      "Bitbucket source" => [
        "https://bitbucket.org/organization/repository/src/main/README.md",
        "https://bitbucket.org/organization/repository"
      ]
    }.each do |description, (project_url, expected_source_url)|
      context "when Gallery metadata identifies a #{description} URL" do
        before do
          stub_gallery(project_url: project_url)
        end

        it "returns the canonical repository URL" do
          expect(source_url).to eq(expected_source_url)
        end
      end
    end

    {
      "missing" => nil,
      "empty" => "",
      "malformed" => "not a URL",
      "non-HTTP" => "git@github.com:Pester/Pester.git",
      "credentialed" => "https://user:secret@github.com/Pester/Pester",
      "explicit-default-port" => "https://github.com:443/Pester/Pester",
      "alternate-port" => "https://github.com:444/Pester/Pester",
      "unsupported-host" => "https://example.com/Pester/Pester",
      "embedded-host" => "https://github.com/127.0.0.1:3000/Pester/Pester",
      "unsupported-CodeCommit" => "https://git-codecommit.eu-west-1.amazonaws.com/v1/repos/Pester",
      "non-repository" => "https://www.powershellgallery.com/packages/Pester",
      "GitHub-dot-segment" => "https://github.com/../Pester",
      "GitLab-dot-segment" => "https://gitlab.com/group/../Pester",
      "Bitbucket-dot-segment" => "https://bitbucket.org/./Pester",
      "Azure-dot-segment" => "https://dev.azure.com/organization/../_git/Pester"
    }.each do |description, project_url|
      context "when Gallery project metadata is #{description}" do
        before do
          stub_gallery(project_url: project_url)
        end

        it "does not report a source repository" do
          expect(source_url).to be_nil
        end
      end
    end

    context "when the selected MAR package has no project URI" do
      let(:dependency_name) { "Az.Accounts" }
      let(:dependency_version) { "5.5.2" }

      before do
        stub_mar(project_uri: nil)
        stub_request(:get, gallery_packages_url).to_return(
          status: 200,
          body: gallery_feed(
            entries: [
              gallery_entry(
                version: dependency_version,
                project_url: "https://github.com/Azure/azure-powershell"
              )
            ]
          )
        )
      end

      it "returns nil without replacing authoritative MAR metadata from Gallery" do
        expect(source_url).to be_nil
        expect(a_request(:get, mar_manifest_url)).to have_been_made.once
        expect(a_request(:get, gallery_packages_url)).not_to have_been_made
      end
    end

    context "when the dependency has no version" do
      let(:dependency_version) { nil }

      it "returns nil without selecting or requesting a registry" do
        expect(source_url).to be_nil
        expect(a_request(:get, /mcr\.microsoft\.com/)).not_to have_been_made
        expect(a_request(:get, /powershellgallery\.com/)).not_to have_been_made
      end
    end

    context "when Microsoft Artifact Registry fails before source selection" do
      before do
        stub_request(:get, mar_tags_url).to_return(status: 500, body: "")
      end

      it "propagates the registry error without falling back" do
        expect { source_url }.to raise_error(Dependabot::RegistryError) do |error|
          expect(error.status).to eq(500)
        end
        expect(a_request(:get, gallery_packages_url)).not_to have_been_made
      end
    end

    context "when selected MAR manifest metadata is malformed" do
      let(:dependency_name) { "Az.Accounts" }
      let(:dependency_version) { "5.5.2" }

      before do
        stub_request(:get, mar_tags_url).to_return(
          status: 200,
          body: JSON.dump("name" => "psresource/az.accounts", "tags" => [dependency_version])
        )
        stub_request(:get, mar_manifest_url).to_return(
          status: 200,
          body: JSON.dump(
            "schemaVersion" => 2,
            "layers" => [{
              "annotations" => { "metadata" => "{" }
            }]
          )
        )
      end

      it "propagates a resolvability error without falling back" do
        expect { source_url }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          /Microsoft Artifact Registry.*Az\.Accounts.*malformed metadata/i
        )
        expect(a_request(:get, gallery_packages_url)).not_to have_been_made
      end
    end

    context "when Gallery fails after the initial MAR 404" do
      before do
        stub_request(:get, mar_tags_url).to_return(status: 404, body: "")
        stub_request(:get, gallery_packages_url).to_return(status: 503, body: "")
      end

      it "propagates the selected Gallery registry error" do
        expect { source_url }.to raise_error(Dependabot::RegistryError) do |error|
          expect(error.status).to eq(503)
        end
      end
    end
  end
end
