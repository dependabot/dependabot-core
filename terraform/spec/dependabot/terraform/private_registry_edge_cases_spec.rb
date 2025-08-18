# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/terraform/metadata_finder"
require "dependabot/terraform/registry_client"

RSpec.describe "Private Registry Edge Cases and Error Scenarios" do
  let(:private_hostname) { "private-registry.example.com" }
  let(:logger) { instance_double("Logger") }

  before do
    allow(Dependabot).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
  end

  describe "RegistryClient edge cases" do
    let(:credentials) do
      [{ "type" => "terraform_registry", "host" => private_hostname, "token" => "test-token" }]
    end
    let(:client) { Dependabot::Terraform::RegistryClient.new(hostname: private_hostname, credentials: credentials) }

    context "malformed registry responses" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "1.0.0",
          package_manager: "terraform",
          requirements: [{
            requirement: "1.0.0",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: private_hostname,
              module_identifier: "company/vpc/aws"
            }
          }]
        )
      end

      it "handles missing X-Terraform-Get header gracefully" do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204) # Missing X-Terraform-Get header

        expect(logger).to receive(:warn).with(
          /Private registry error: KeyError/
        )

        expect { client.source(dependency: dependency) }.to raise_error(KeyError)
      end

      it "handles malformed service discovery response" do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: "invalid json")

        expect(logger).to receive(:warn).with(
          /Private registry error: JSON::ParserError/
        )

        result = client.source(dependency: dependency)
        expect(result).to be_nil
      end

      it "handles empty service discovery response" do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: {}.to_json)

        expect { client.source(dependency: dependency) }.to raise_error(/Host does not support required Terraform-native service/)
      end
    end

    context "authentication edge cases" do
      it "handles expired tokens" do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(
            status: 401,
            body: { error: "Token expired" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        dependency = Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "1.0.0",
          package_manager: "terraform",
          requirements: [{
            requirement: "1.0.0",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: private_hostname,
              module_identifier: "company/vpc/aws"
            }
          }]
        )

        expect(logger).to receive(:warn).with(
          /Private registry error: StandardError.*Authentication failed.*status: 401.*has_credentials: true/
        )

        expect { client.source(dependency: dependency) }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end

      it "handles invalid token format" do
        invalid_credentials = [{ "type" => "terraform_registry", "host" => private_hostname, "token" => "" }]
        client_with_invalid_token = Dependabot::Terraform::RegistryClient.new(
          hostname: private_hostname,
          credentials: invalid_credentials
        )

        expect(logger).to receive(:info).with(
          /Private registry operation: authentication_setup.*has_token: false.*token_length: 0/
        )

        headers = client_with_invalid_token.send(:headers_for, private_hostname)
        expect(headers).not_to include("Authorization")
      end
    end

    context "network edge cases" do
      it "handles DNS resolution failures" do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_raise(Excon::Error::Socket.new(nil, "getaddrinfo: Name or service not known"))

        dependency = Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "1.0.0",
          package_manager: "terraform",
          requirements: [{
            requirement: "1.0.0",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: private_hostname,
              module_identifier: "company/vpc/aws"
            }
          }]
        )

        expect { client.source(dependency: dependency) }.to raise_error(Dependabot::PrivateSourceBadResponse)
      end

      it "handles SSL certificate failures" do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_raise(Excon::Error::Certificate.new(nil, "SSL certificate verify failed"))

        dependency = Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "1.0.0",
          package_manager: "terraform",
          requirements: [{
            requirement: "1.0.0",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: private_hostname,
              module_identifier: "company/vpc/aws"
            }
          }]
        )

        expect { client.source(dependency: dependency) }.to raise_error(Excon::Error::Certificate)
      end
    end
  end

  describe "MetadataFinder edge cases" do
    let(:credentials) do
      [
        { "type" => "terraform_registry", "host" => private_hostname, "token" => "registry-token" },
        { "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "git-token" }
      ]
    end

    context "dependency configuration edge cases" do
      it "handles dependency with missing source information" do
        dependency = Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "1.0.0",
          package_manager: "terraform",
          requirements: [{
            requirement: "1.0.0",
            groups: [],
            file: "main.tf",
            source: {} # Empty source
          }]
        )

        finder = Dependabot::Terraform::MetadataFinder.new(
          dependency: dependency,
          credentials: credentials
        )

        expect { finder.source_url }.to raise_error(KeyError)
      end

      it "handles dependency with mixed source types" do
        dependency = Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "1.0.0",
          package_manager: "terraform",
          requirements: [
            {
              requirement: "1.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: private_hostname,
                module_identifier: "company/vpc/aws"
              }
            },
            {
              requirement: "1.0.0",
              groups: [],
              file: "other.tf",
              source: {
                type: "git",
                url: "https://github.com/company/terraform-vpc"
              }
            }
          ]
        )

        finder = Dependabot::Terraform::MetadataFinder.new(
          dependency: dependency,
          credentials: credentials
        )

        # Should raise an error due to multiple sources
        expect { dependency.source_type }.to raise_error(RuntimeError, /Multiple sources!/)
      end

      it "handles dependency with no requirements" do
        dependency = Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "1.0.0",
          package_manager: "terraform",
          requirements: []
        )

        finder = Dependabot::Terraform::MetadataFinder.new(
          dependency: dependency,
          credentials: credentials
        )

        expect { finder.source_url }.to raise_error
      end
    end

    context "source resolution edge cases" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "1.0.0",
          package_manager: "terraform",
          requirements: [{
            requirement: "1.0.0",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: private_hostname,
              module_identifier: "company/vpc/aws"
            }
          }]
        )
      end

      let(:finder) do
        Dependabot::Terraform::MetadataFinder.new(
          dependency: dependency,
          credentials: credentials
        )
      end

      it "handles relative URLs in X-Terraform-Get header" do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "./terraform-vpc" })

        # When RegistryClient.get_proxied_source is called with a relative URL that's been joined,
        # it will try to process it. We need to mock that behavior
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/terraform-vpc?terraform-get=1")
          .to_return(status: 200, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")
      end

      it "handles archive URLs in X-Terraform-Get header" do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "https://github.com/company/terraform-vpc/archive/v1.0.0.zip" })

        # Should not try to proxy archive URLs
        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")
      end

      it "handles HTTP URLs that need proxying" do
        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "https://example.com/terraform-vpc" })

        # Mock the proxying request
        stub_request(:get, "https://example.com/terraform-vpc?terraform-get=1")
          .to_return(status: 200, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/company/terraform-vpc")
      end
    end

    context "credential filtering edge cases" do
      let(:complex_credentials) do
        [
          { "type" => "terraform_registry", "host" => private_hostname, "token" => "registry-token" },
          { "type" => "terraform_registry", "host" => "other-registry.com", "token" => "other-token" },
          { "type" => "git_source", "host" => "github.com", "username" => "user", "password" => "pass" },
          { "type" => "git_source", "host" => "gitlab.com", "username" => "user", "password" => "pass" },
          { "type" => "npm_registry", "host" => "npm.example.com", "token" => "npm-token" },
          { "type" => "unknown_type", "host" => "unknown.com", "token" => "unknown-token" }
        ]
      end

      let(:finder) do
        Dependabot::Terraform::MetadataFinder.new(
          dependency: Dependabot::Dependency.new(
            name: "company/vpc/aws",
            version: "1.0.0",
            package_manager: "terraform",
            requirements: [{
              requirement: "1.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: private_hostname,
                module_identifier: "company/vpc/aws"
              }
            }]
          ),
          credentials: complex_credentials
        )
      end

      it "filters credentials appropriately for the target hostname" do
        expect(logger).to receive(:info).with(
          /Private registry operation: credential_filtering.*total_credentials: 6.*relevant_credentials: 5.*credential_types: \["terraform_registry", "git_source", "npm_registry", "unknown_type"\]/
        )

        result = finder.send(:enhanced_credentials_for_source, private_hostname)
        expect(result.length).to eq(5)

        # Should include the correct terraform_registry credential
        terraform_cred = result.find { |c| c["type"] == "terraform_registry" }
        expect(terraform_cred["host"]).to eq(private_hostname)
        expect(terraform_cred["token"]).to eq("registry-token")
      end
    end
  end

  describe "integration edge cases" do
    let(:credentials) do
      [
        { "type" => "terraform_registry", "host" => private_hostname, "token" => "registry-token" },
        { "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "git-token" }
      ]
    end

    context "version mismatch scenarios" do
      it "handles dependency version not found in changelog" do
        dependency = Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "2.0.0", # Version not in our test changelog
          previous_version: "1.0.0",
          package_manager: "terraform",
          requirements: [{
            requirement: "2.0.0",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: private_hostname,
              module_identifier: "company/vpc/aws"
            }
          }]
        )

        finder = Dependabot::Terraform::MetadataFinder.new(
          dependency: dependency,
          credentials: credentials
        )

        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/2.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

        changelog_content = File.read(File.join(__dir__, "../../fixtures/github/company_terraform_vpc_changelog.md"))
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

        # Should still return changelog text even if specific version not found
        changelog_text = finder.changelog_text
        expect(changelog_text).not_to be_nil
        expect(changelog_text).to include("# Changelog")
      end
    end

    context "unicode and encoding edge cases" do
      it "handles non-UTF8 changelog content" do
        dependency = Dependabot::Dependency.new(
          name: "company/vpc/aws",
          version: "1.0.0",
          package_manager: "terraform",
          requirements: [{
            requirement: "1.0.0",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: private_hostname,
              module_identifier: "company/vpc/aws"
            }
          }]
        )

        finder = Dependabot::Terraform::MetadataFinder.new(
          dependency: dependency,
          credentials: credentials
        )

        stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })

        # Create content with invalid UTF-8 bytes
        invalid_content = "# Changelog\n\n## [1.0.0]\n\nSome content with invalid bytes: \xFF\xFE"
        encoded_content = Base64.encode64(invalid_content)

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

        # Should handle invalid encoding gracefully
        changelog_text = finder.changelog_text
        expect(changelog_text).to be_nil # Invalid encoding should be rejected
      end
    end
  end
end
