# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/terraform/metadata_finder"

RSpec.describe "Graceful Degradation for Private Registry Changelog" do
  let(:private_hostname) { "private-registry.example.com" }
  let(:logger) { instance_double("Logger") }
  let(:credentials) do
    [
      {
        "type" => "terraform_registry",
        "host" => private_hostname,
        "token" => "private-registry-token"
      },
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "github-token"
      }
    ]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "company/vpc/aws",
      version: "1.0.0",
      previous_version: "0.9.0",
      requirements: [{
        requirement: "1.0.0",
        groups: [],
        file: "main.tf",
        source: {
          type: "registry",
          registry_hostname: private_hostname,
          module_identifier: "company/vpc/aws"
        }
      }],
      previous_requirements: [{
        requirement: "0.9.0",
        groups: [],
        file: "main.tf",
        source: {
          type: "registry",
          registry_hostname: private_hostname,
          module_identifier: "company/vpc/aws"
        }
      }],
      package_manager: "terraform"
    )
  end

  let(:finder) do
    Dependabot::Terraform::MetadataFinder.new(
      dependency: dependency,
      credentials: credentials
    )
  end

  before do
    allow(Dependabot).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
  end

  describe "graceful degradation scenarios" do
    context "registry accessible but source repository inaccessible" do
      before do
        # Registry works fine
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

        # But source repository is inaccessible
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_return(status: 404)
      end

      it "provides source URL but gracefully handles changelog failure" do
        # Source URL should work
        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")

        # Changelog operations should return nil gracefully
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil

        changelog_url = finder.changelog_url
        expect(changelog_url).to be_nil

        releases_text = finder.releases_text
        expect(releases_text).to be_nil

        releases_url = finder.releases_url
        expect(releases_url).to be_nil

        # Homepage URL should still work (from source)
        homepage_url = finder.homepage_url
        expect(homepage_url).to eq("https://github.com/company/terraform-vpc")
      end
    end

    context "partial source repository access" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

        # Contents API works
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_return(
            status: 200,
            body: [
              {
                name: "CHANGELOG.md",
                type: "file",
                size: 2000,
                download_url: "https://raw.githubusercontent.com/company/terraform-vpc/main/CHANGELOG.md",
                html_url: "https://github.com/company/terraform-vpc/blob/main/CHANGELOG.md",
                url: "https://api.github.com/repos/company/terraform-vpc/contents/CHANGELOG.md"
              }
            ].to_json
          )

        # But file content API fails
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents/CHANGELOG.md")
          .to_return(status: 403) # Forbidden

        # Releases API works
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/releases")
          .to_return(
            status: 200,
            body: [
              {
                tag_name: "v1.0.0",
                name: "v1.0.0 - Stable Release",
                body: "Initial stable release",
                html_url: "https://github.com/company/terraform-vpc/releases/tag/v1.0.0"
              }
            ].to_json
          )
      end

      it "provides available information and gracefully handles failures" do
        # Source URL should work
        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")

        # Changelog should fail gracefully (file content not accessible)
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil

        changelog_url = finder.changelog_url
        expect(changelog_url).to be_nil

        # But releases should work
        releases_text = finder.releases_text
        expect(releases_text).to include("Initial stable release")

        releases_url = finder.releases_url
        expect(releases_url).to eq("https://github.com/company/terraform-vpc/releases")
      end
    end

    context "network instability" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })
      end

      it "handles intermittent network failures gracefully" do
        # First call fails with timeout
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_raise(Excon::Error::Timeout).then
          .to_return(
            status: 200,
            body: [
              {
                name: "CHANGELOG.md",
                type: "file",
                size: 2000,
                download_url: "https://raw.githubusercontent.com/company/terraform-vpc/main/CHANGELOG.md",
                html_url: "https://github.com/company/terraform-vpc/blob/main/CHANGELOG.md",
                url: "https://api.github.com/repos/company/terraform-vpc/contents/CHANGELOG.md"
              }
            ].to_json
          )

        # First changelog call should fail gracefully
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil

        # Source URL should still work
        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")
      end
    end

    context "malformed responses" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_return(status: 200, body: "invalid json")
      end

      it "handles malformed JSON responses gracefully" do
        # Should not raise an error, should return nil
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil

        # Source URL should still work
        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")
      end
    end

    context "missing credentials for source repository" do
      let(:credentials_without_git) do
        [
          {
            "type" => "terraform_registry",
            "host" => private_hostname,
            "token" => "private-registry-token"
          }
          # No git_source credentials
        ]
      end

      let(:finder_without_git_creds) do
        Dependabot::Terraform::MetadataFinder.new(
          dependency: dependency,
          credentials: credentials_without_git
        )
      end

      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

        # GitHub API returns 401 due to missing credentials
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_return(status: 401)
      end

      it "handles missing source repository credentials gracefully" do
        # Registry operations should work (has registry credentials)
        source_url = finder_without_git_creds.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")

        # Source repository operations should fail gracefully (no git credentials)
        changelog_text = finder_without_git_creds.changelog_text
        expect(changelog_text).to be_nil

        releases_text = finder_without_git_creds.releases_text
        expect(releases_text).to be_nil
      end
    end
  end

  describe "error logging without sensitive information exposure" do
    before do
      stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
        .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
      stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
        .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })
      stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
        .to_return(status: 403, body: { message: "Bad credentials" }.to_json)
    end

    it "logs errors without exposing sensitive credential information" do
      expect(logger).to receive(:info).at_least(:once)
      expect(logger).not_to receive(:info).with(/private-registry-token/)
      expect(logger).not_to receive(:info).with(/github-token/)
      expect(logger).not_to receive(:warn).with(/private-registry-token/)
      expect(logger).not_to receive(:warn).with(/github-token/)

      # Trigger operations that will cause logging
      finder.source_url
      finder.changelog_text
    end
  end
end
