# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/terraform/metadata_finder"

RSpec.describe "Private Registry Changelog Integration" do
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

  before do
    allow(Dependabot).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
  end

  describe "end-to-end private registry changelog retrieval" do
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

    context "successful private registry with GitHub source" do
      before do
        # Mock private registry service discovery
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(
            status: 200,
            body: { "modules.v1": "/v1/modules/" }.to_json
          )

        # Mock private registry module download endpoint
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .with(headers: { "Authorization" => "Bearer private-registry-token" })
          .to_return(
            status: 204,
            headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" }
          )

        # Mock GitHub API calls for changelog and releases
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .with(headers: { "Authorization" => "token github-token" })
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

        # Mock GitHub file content API
        changelog_content = File.read("terraform/spec/fixtures/github/company_terraform_vpc_changelog.md")
        encoded_content = Base64.encode64(changelog_content)
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents/CHANGELOG.md")
          .with(headers: { "Authorization" => "token github-token" })
          .to_return(
            status: 200,
            body: {
              name: "CHANGELOG.md",
              content: encoded_content,
              encoding: "base64"
            }.to_json
          )

        # Mock GitHub releases API
        releases_content = File.read("terraform/spec/fixtures/github/company_terraform_vpc_releases.json")
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/releases")
          .with(headers: { "Authorization" => "token github-token" })
          .to_return(
            status: 200,
            body: releases_content
          )
      end

      it "successfully retrieves source URL from private registry" do
        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")
      end

      it "successfully retrieves changelog URL" do
        changelog_url = finder.changelog_url
        expect(changelog_url).to eq("https://github.com/company/terraform-vpc/blob/main/CHANGELOG.md")
      end

      it "successfully retrieves and prunes changelog text" do
        changelog_text = finder.changelog_text

        expect(changelog_text).to include("## [1.0.0] - 2024-01-15")
        expect(changelog_text).to include("### Added")
        expect(changelog_text).to include("Initial stable release of the VPC module")
        expect(changelog_text).to include("## [0.9.0] - 2024-01-10")

        # Should not include older versions that are not relevant
        expect(changelog_text).not_to include("## [0.8.0] - 2024-01-05")
      end

      it "successfully retrieves releases URL" do
        releases_url = finder.releases_url
        expect(releases_url).to eq("https://github.com/company/terraform-vpc/releases")
      end

      it "successfully retrieves releases text" do
        releases_text = finder.releases_text

        expect(releases_text).to include("v1.0.0 - Stable Release")
        expect(releases_text).to include("Initial stable release of the VPC module")
        expect(releases_text).to include("Fixed issue with route table associations")
        expect(releases_text).to include("v0.9.0 - Beta Release")
      end

      it "logs all private registry operations" do
        expect(logger).to receive(:info).with(
          /Private registry operation: metadata_finder_source_lookup/,
          hash_including(hostname: private_hostname)
        )
        expect(logger).to receive(:info).with(
          /Private registry operation: source_resolution/,
          hash_including(hostname: private_hostname)
        )
        expect(logger).to receive(:info).with(
          /Private registry operation: metadata_finder_source_resolved/,
          hash_including(hostname: private_hostname)
        )

        # Trigger the operations
        finder.source_url
        finder.changelog_text
        finder.releases_text
      end
    end

    context "private registry with authentication failure" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(
            status: 200,
            body: { "modules.v1": "/v1/modules/" }.to_json
          )

        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 401)
      end

      it "raises authentication failure and logs appropriately" do
        expect(logger).to receive(:warn).with(
          /Private registry error: PrivateSourceAuthenticationFailure/,
          hash_including(
            hostname: private_hostname,
            error_type: "authentication_failure"
          )
        )

        expect { finder.source_url }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "private registry with source repository access failure" do
      before do
        # Private registry works fine
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(
            status: 200,
            body: { "modules.v1": "/v1/modules/" }.to_json
          )

        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .with(headers: { "Authorization" => "Bearer private-registry-token" })
          .to_return(
            status: 204,
            headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" }
          )

        # But GitHub access fails
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_return(status: 404)
      end

      it "successfully gets source URL but gracefully handles changelog access failure" do
        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")

        # Changelog should be nil due to source repository access failure
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil

        changelog_url = finder.changelog_url
        expect(changelog_url).to be_nil
      end
    end

    context "private registry with GitLab source" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(
            status: 200,
            body: { "modules.v1": "/v1/modules/" }.to_json
          )

        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .with(headers: { "Authorization" => "Bearer private-registry-token" })
          .to_return(
            status: 204,
            headers: { "X-Terraform-Get" => "git::https://gitlab.com/company/terraform-vpc" }
          )

        # Mock GitLab API calls
        stub_request(:get, "https://gitlab.com/api/v4/projects/company%2Fterraform-vpc/repository/tree")
          .to_return(
            status: 200,
            body: [
              {
                name: "CHANGELOG.md",
                type: "blob",
                path: "CHANGELOG.md"
              }
            ].to_json
          )
      end

      it "successfully resolves GitLab source" do
        source_url = finder.source_url
        expect(source_url).to eq("https://gitlab.com/company/terraform-vpc")
      end
    end

    context "private registry with network timeout" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_raise(Excon::Error::Timeout)
      end

      it "handles network timeouts gracefully" do
        expect(logger).to receive(:warn).with(
          /Private registry error: PrivateSourceBadResponse/,
          hash_including(hostname: private_hostname)
        )

        expect { finder.source_url }.to raise_error(Dependabot::PrivateSourceBadResponse)
      end
    end
  end

  describe "changelog formatting consistency" do
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

    let(:public_dependency) do
      Dependabot::Dependency.new(
        name: "hashicorp/consul/aws",
        version: "0.3.8",
        previous_version: "0.1.0",
        requirements: [{
          requirement: "0.3.8",
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "registry.terraform.io",
            module_identifier: "hashicorp/consul/aws"
          }
        }],
        previous_requirements: [{
          requirement: "0.1.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "registry.terraform.io",
            module_identifier: "hashicorp/consul/aws"
          }
        }],
        package_manager: "terraform"
      )
    end

    let(:private_finder) do
      Dependabot::Terraform::MetadataFinder.new(
        dependency: dependency,
        credentials: credentials
      )
    end

    let(:public_finder) do
      Dependabot::Terraform::MetadataFinder.new(
        dependency: public_dependency,
        credentials: credentials
      )
    end

    before do
      # Setup private registry mocks
      stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
        .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
      stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
        .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

      # Setup public registry mocks
      stub_request(:get, "https://registry.terraform.io/.well-known/terraform.json")
        .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
      stub_request(:get, "https://registry.terraform.io/v1/modules/hashicorp/consul/aws/0.3.8/download")
        .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/hashicorp/terraform-aws-consul" })
    end

    it "provides consistent source_url format for both private and public registries" do
      private_source_url = private_finder.source_url
      public_source_url = public_finder.source_url

      expect(private_source_url).to match(/^https:\/\/github\.com\//)
      expect(public_source_url).to match(/^https:\/\/github\.com\//)

      # Both should be valid URLs
      expect { URI.parse(private_source_url) }.not_to raise_error
      expect { URI.parse(public_source_url) }.not_to raise_error
    end
  end

  describe "performance and reliability" do
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

    context "network timeout handling" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })
      end

      it "handles GitHub API timeouts gracefully" do
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_raise(Excon::Error::Timeout)

        # Should not raise an error, should return nil gracefully
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil

        changelog_url = finder.changelog_url
        expect(changelog_url).to be_nil
      end

      it "handles connection failures gracefully" do
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_raise(Excon::Error::Socket.new("Connection refused"))

        # Should not raise an error, should return nil gracefully
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil
      end
    end

    context "rate limiting scenarios" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })
      end

      it "handles GitHub API rate limiting" do
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_return(
            status: 403,
            headers: {
              "X-RateLimit-Limit" => "5000",
              "X-RateLimit-Remaining" => "0",
              "X-RateLimit-Reset" => (Time.now + 3600).to_i.to_s
            },
            body: {
              message: "API rate limit exceeded",
              documentation_url: "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"
            }.to_json
          )

        # Should handle rate limiting gracefully
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil
      end

      it "handles private registry rate limiting" do
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 429, headers: { "Retry-After" => "60" })

        expect(logger).to receive(:warn).with(
          /Private registry error: StandardError/,
          hash_including(
            hostname: private_hostname,
            error_message: "Response from registry was 429"
          )
        )

        expect { finder.source_url }.to raise_error(Dependabot::DependabotError, /Response from registry was 429/)
      end
    end

    context "large changelog handling" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })
      end

      it "handles very large changelog files" do
        # Create a large changelog content (simulate a file with many versions)
        large_changelog = "# Changelog\n\n"
        (1..100).each do |i|
          large_changelog += "## [#{i}.0.0] - 2024-01-#{i.to_s.rjust(2, '0')}\n\n"
          large_changelog += "### Added\n- Feature #{i}\n\n"
          large_changelog += "### Fixed\n- Bug fix #{i}\n\n"
        end

        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_return(
            status: 200,
            body: [
              {
                name: "CHANGELOG.md",
                type: "file",
                size: large_changelog.length,
                download_url: "https://raw.githubusercontent.com/company/terraform-vpc/main/CHANGELOG.md",
                html_url: "https://github.com/company/terraform-vpc/blob/main/CHANGELOG.md",
                url: "https://api.github.com/repos/company/terraform-vpc/contents/CHANGELOG.md"
              }
            ].to_json
          )

        encoded_content = Base64.encode64(large_changelog)
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents/CHANGELOG.md")
          .to_return(
            status: 200,
            body: {
              name: "CHANGELOG.md",
              content: encoded_content,
              encoding: "base64"
            }.to_json
          )

        # Should handle large changelog and prune appropriately
        changelog_text = finder.changelog_text
        expect(changelog_text).not_to be_nil
        expect(changelog_text.length).to be < large_changelog.length # Should be pruned
        expect(changelog_text).to include("## [1.0.0]") # Should include new version
      end

      it "skips extremely large files to prevent memory issues" do
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents")
          .to_return(
            status: 200,
            body: [
              {
                name: "CHANGELOG.md",
                type: "file",
                size: 2_000_000, # 2MB file - should be skipped
                download_url: "https://raw.githubusercontent.com/company/terraform-vpc/main/CHANGELOG.md",
                html_url: "https://github.com/company/terraform-vpc/blob/main/CHANGELOG.md",
                url: "https://api.github.com/repos/company/terraform-vpc/contents/CHANGELOG.md"
              }
            ].to_json
          )

        # Should skip the large file and return nil
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil
      end
    end

    context "concurrent operations" do
      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

        changelog_content = File.read("terraform/spec/fixtures/github/company_terraform_vpc_changelog.md")
        encoded_content = Base64.encode64(changelog_content)

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

        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/contents/CHANGELOG.md")
          .to_return(
            status: 200,
            body: {
              name: "CHANGELOG.md",
              content: encoded_content,
              encoding: "base64"
            }.to_json
          )

        releases_content = File.read("terraform/spec/fixtures/github/company_terraform_vpc_releases.json")
        stub_request(:get, "https://api.github.com/repos/company/terraform-vpc/releases")
          .to_return(status: 200, body: releases_content)
      end

      it "handles concurrent metadata finder operations safely" do
        threads = []
        results = {}

        # Create multiple threads accessing different metadata
        5.times do |i|
          threads << Thread.new do
            case i % 3
            when 0
              results["source_url_#{i}"] = finder.source_url
            when 1
              results["changelog_text_#{i}"] = finder.changelog_text
            when 2
              results["releases_text_#{i}"] = finder.releases_text
            end
          end
        end

        threads.each(&:join)

        # All operations should complete successfully
        expect(results["source_url_0"]).to eq("https://github.com/company/terraform-vpc")
        expect(results["changelog_text_1"]).to include("## [1.0.0] - 2024-01-15")
        expect(results["releases_text_2"]).to include("v1.0.0 - Stable Release")
      end
    end

    context "memory usage with multiple dependencies" do
      let(:dependencies) do
        (1..10).map do |i|
          Dependabot::Dependency.new(
            name: "company/module#{i}/aws",
            version: "1.0.0",
            previous_version: "0.9.0",
            requirements: [{
              requirement: "1.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: private_hostname,
                module_identifier: "company/module#{i}/aws"
              }
            }],
            package_manager: "terraform"
          )
        end
      end

      before do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)

        dependencies.each do |dep|
          stub_request(:get, "https://#{private_hostname}/v1/modules/#{dep.name}/1.0.0/download")
            .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-#{dep.name.split('/')[1]}" })
        end
      end

      it "handles multiple metadata finders without excessive memory usage" do
        finders = dependencies.map do |dep|
          Dependabot::Terraform::MetadataFinder.new(
            dependency: dep,
            credentials: credentials
          )
        end

        # Process all finders - should not cause memory issues
        source_urls = finders.map(&:source_url)

        expect(source_urls).to all(match(/^https:\/\/github\.com\/company\/terraform-/))
        expect(source_urls.length).to eq(10)
      end
    end
  end
end
