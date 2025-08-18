# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/terraform/metadata_finder"
require "dependabot/terraform/registry_client"

RSpec.describe "Regression Verification for Enhanced Private Registry Support" do
  describe "public registry functionality remains intact" do
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

    let(:credentials) do
      [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    end

    let(:finder) do
      Dependabot::Terraform::MetadataFinder.new(
        dependency: public_dependency,
        credentials: credentials
      )
    end

    let(:logger) { instance_double("Logger") }

    before do
      allow(Dependabot).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
    end

    context "RegistryClient public registry operations" do
      let(:client) { Dependabot::Terraform::RegistryClient.new }

      before do
        stub_request(:get, "https://registry.terraform.io/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://registry.terraform.io/v1/modules/hashicorp/consul/aws/0.3.8/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/hashicorp/terraform-aws-consul" })
      end

      it "resolves public registry sources without private registry logging" do
        # Should NOT receive private registry logging for public registry
        expect(logger).not_to receive(:info).with(/Private registry operation/)
        expect(logger).not_to receive(:warn).with(/Private registry error/)

        source = client.source(dependency: public_dependency)
        expect(source).to be_a(Dependabot::Source)
        expect(source.url).to eq("https://github.com/hashicorp/terraform-aws-consul")
      end

      it "does not add enhanced headers for public registry" do
        headers = client.send(:headers_for, "registry.terraform.io")
        expect(headers).not_to include("User-Agent")
        expect(headers).to eq({}) # Should be empty for public registry without credentials
      end

      it "validates credentials correctly for public registry" do
        # Should return true for public registry (no validation needed)
        result = client.send(:validate_credentials_for_hostname, "registry.terraform.io")
        expect(result).to be true
      end
    end

    context "MetadataFinder public registry operations" do
      before do
        stub_request(:get, "https://registry.terraform.io/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://registry.terraform.io/v1/modules/hashicorp/consul/aws/0.3.8/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/hashicorp/terraform-aws-consul" })
      end

      it "resolves public registry metadata without private registry logging" do
        # Should NOT receive private registry logging for public registry
        expect(logger).not_to receive(:info).with(/Private registry operation/)
        expect(logger).not_to receive(:warn).with(/Private registry error/)

        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/hashicorp/terraform-aws-consul")
      end

      it "maintains existing public registry behavior" do
        source_url = finder.source_url
        homepage_url = finder.homepage_url

        expect(source_url).to eq("https://github.com/hashicorp/terraform-aws-consul")
        expect(homepage_url).to eq("https://github.com/hashicorp/terraform-aws-consul")
      end
    end
  end

  describe "git dependency functionality remains intact" do
    let(:git_dependency) do
      Dependabot::Dependency.new(
        name: "origin_label",
        version: "tags/0.4.1",
        previous_version: nil,
        requirements: [{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-null.git",
            branch: nil,
            ref: "tags/0.4.1"
          }
        }],
        previous_requirements: [{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-null.git",
            branch: nil,
            ref: "tags/0.3.7"
          }
        }],
        package_manager: "terraform"
      )
    end

    let(:credentials) do
      [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    end

    let(:finder) do
      Dependabot::Terraform::MetadataFinder.new(
        dependency: git_dependency,
        credentials: credentials
      )
    end

    let(:logger) { instance_double("Logger") }

    before do
      allow(Dependabot).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
    end

    it "resolves git dependencies without private registry logging" do
      # Should NOT receive private registry logging for git dependencies
      expect(logger).not_to receive(:info).with(/Private registry operation/)
      expect(logger).not_to receive(:warn).with(/Private registry error/)

      source_url = finder.source_url
      expect(source_url).to eq("https://github.com/cloudposse/terraform-null")
    end

    it "maintains existing git dependency behavior" do
      source_url = finder.source_url
      homepage_url = finder.homepage_url

      expect(source_url).to eq("https://github.com/cloudposse/terraform-null")
      expect(homepage_url).to eq("https://github.com/cloudposse/terraform-null")
    end
  end

  describe "provider dependency functionality remains intact" do
    let(:provider_dependency) do
      Dependabot::Dependency.new(
        name: "hashicorp/aws",
        version: "3.40.0",
        previous_version: "0.1.0",
        requirements: [{
          requirement: "3.40.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "provider",
            registry_hostname: "registry.terraform.io",
            module_identifier: "hashicorp/aws"
          }
        }],
        previous_requirements: [{
          requirement: "0.1.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "provider",
            registry_hostname: "registry.terraform.io",
            module_identifier: "hashicorp/aws"
          }
        }],
        package_manager: "terraform"
      )
    end

    let(:credentials) do
      [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    end

    let(:finder) do
      Dependabot::Terraform::MetadataFinder.new(
        dependency: provider_dependency,
        credentials: credentials
      )
    end

    let(:logger) { instance_double("Logger") }

    before do
      allow(Dependabot).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)

      stub_request(:get, "https://registry.terraform.io/.well-known/terraform.json")
        .to_return(status: 200, body: { "providers.v1": "/v1/providers/" }.to_json)
      stub_request(:get, "https://registry.terraform.io/v1/providers/hashicorp/aws/3.40.0")
        .to_return(
          status: 200,
          body: { source: "https://github.com/hashicorp/terraform-provider-aws" }.to_json
        )
    end

    it "resolves provider dependencies without private registry logging" do
      # Should NOT receive private registry logging for public provider registry
      expect(logger).not_to receive(:info).with(/Private registry operation/)
      expect(logger).not_to receive(:warn).with(/Private registry error/)

      source_url = finder.source_url
      expect(source_url).to eq("https://github.com/hashicorp/terraform-provider-aws")
    end

    it "maintains existing provider dependency behavior" do
      source_url = finder.source_url
      homepage_url = finder.homepage_url

      expect(source_url).to eq("https://github.com/hashicorp/terraform-provider-aws")
      expect(homepage_url).to eq("https://github.com/hashicorp/terraform-provider-aws")
    end
  end

  describe "error handling remains intact for public registries" do
    let(:public_dependency) do
      Dependabot::Dependency.new(
        name: "nonexistent/module/aws",
        version: "1.0.0",
        requirements: [{
          requirement: "1.0.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "registry.terraform.io",
            module_identifier: "nonexistent/module/aws"
          }
        }],
        package_manager: "terraform"
      )
    end

    let(:client) { Dependabot::Terraform::RegistryClient.new }
    let(:logger) { instance_double("Logger") }

    before do
      allow(Dependabot).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
    end

    it "maintains existing error handling for public registry failures" do
      stub_request(:get, "https://registry.terraform.io/.well-known/terraform.json")
        .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
      stub_request(:get, "https://registry.terraform.io/v1/modules/nonexistent/module/aws/1.0.0/download")
        .to_return(status: 404)

      # Should NOT receive private registry logging for public registry errors
      expect(logger).not_to receive(:info).with(/Private registry operation/)
      expect(logger).not_to receive(:warn).with(/Private registry error/)

      expect { client.send(:http_get!, URI("https://registry.terraform.io/v1/modules/nonexistent/module/aws/1.0.0/download")) }
        .to raise_error(Dependabot::DependabotError, /Response from registry was 404/)
    end
  end

  describe "mixed public and private registry scenarios" do
    let(:mixed_credentials) do
      [
        { "type" => "terraform_registry", "host" => "private-registry.example.com", "token" => "private-token" },
        { "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "git-token" }
      ]
    end

    context "public registry with private registry credentials present" do
      let(:public_dependency) do
        Dependabot::Dependency.new(
          name: "hashicorp/consul/aws",
          version: "0.3.8",
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
          package_manager: "terraform"
        )
      end

      let(:finder) do
        Dependabot::Terraform::MetadataFinder.new(
          dependency: public_dependency,
          credentials: mixed_credentials
        )
      end

      let(:logger) { instance_double("Logger") }

      before do
        allow(Dependabot).to receive(:logger).and_return(logger)
        allow(logger).to receive(:info)
        allow(logger).to receive(:warn)

        stub_request(:get, "https://registry.terraform.io/.well-known/terraform.json")
          .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
        stub_request(:get, "https://registry.terraform.io/v1/modules/hashicorp/consul/aws/0.3.8/download")
          .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/hashicorp/terraform-aws-consul" })
      end

      it "handles public registry correctly even with private registry credentials present" do
        # Should NOT receive private registry logging for public registry
        expect(logger).not_to receive(:info).with(/Private registry operation/)
        expect(logger).not_to receive(:warn).with(/Private registry error/)

        source_url = finder.source_url
        expect(source_url).to eq("https://github.com/hashicorp/terraform-aws-consul")
      end
    end
  end
end
