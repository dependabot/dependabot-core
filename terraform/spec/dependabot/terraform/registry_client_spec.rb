# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform/registry_client"

RSpec.describe Dependabot::Terraform::RegistryClient do
  subject(:client) { described_class.new }

  let(:module_dependency) do
    Dependabot::Dependency.new(
      name: "hashicorp/consul/aws",
      version: "0.9.3",
      package_manager: "terraform",
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
      }]
    )
  end

  it "fetches provider versions", :vcr do
    response = client.all_provider_versions(identifier: "hashicorp/aws")
    expect(response.max).to eq(Gem::Version.new("3.42.0"))
  end

  it "fetches provider versions from a custom registry" do
    hostname = "registry.example.org"
    stub_request(:get, "https://#{hostname}/.well-known/terraform.json").and_return(
      status: 200,
      body: {
        "modules.v1": "/v1/modules/",
        "providers.v1": "/v1/providers/"
      }.to_json
    )
    stub_request(:get, "https://#{hostname}/v1/providers/hashicorp/aws/versions").and_return(
      status: 200,
      body: {
        id: "hashicorp/aws",
        versions: [{ version: "3.42.0" }, { version: "3.41.0" }]
      }.to_json
    )
    client = described_class.new(hostname: hostname)
    response = client.all_provider_versions(identifier: "hashicorp/aws")
    expect(response).to contain_exactly(Gem::Version.new("3.42.0"), Gem::Version.new("3.41.0"))
  end

  it "raises an error when the registry does not support the provider API" do
    hostname = "registry.example.org"
    stub_request(:get, "https://#{hostname}/.well-known/terraform.json").and_return(
      status: 200,
      body: { "modules.v1": "/v1/modules/" }.to_json
    )
    client = described_class.new(hostname: hostname)

    expect do
      client.all_provider_versions(identifier: "hashicorp/aws")
    end.to raise_error(/Host does not support required Terraform-native service/)
  end

  it "raises an error when the host does not support the service discovery protocol" do
    hostname = "registry.example.org"
    stub_request(:get, "https://#{hostname}/.well-known/terraform.json").and_return(status: 404)
    client = described_class.new(hostname: hostname)

    expect do
      client.all_provider_versions(identifier: "hashicorp/aws")
    end.to raise_error(/Host does not support required Terraform-native service/)
  end

  it "fetches provider versions form a custom registry secured by a token" do
    hostname = "registry.example.org"
    token = SecureRandom.hex(16)
    credentials = [{ "type" => "terraform_registry", "host" => hostname, "token" => token }]

    stub_request(:get, "https://#{hostname}/.well-known/terraform.json").and_return(body: {
      "modules.v1": "/v1/modules/",
      "providers.v1": "/v1/providers/"
    }.to_json)
    stub_request(:get, "https://#{hostname}/v1/providers/x/y/versions")
      .and_return(body: { id: "x/y", versions: [{ version: "0.1.0" }] }.to_json)
    client = described_class.new(hostname: hostname, credentials: credentials)

    expect(client.all_provider_versions(identifier: "x/y")).to contain_exactly(Gem::Version.new("0.1.0"))
    expect(WebMock).to have_requested(:get, "https://#{hostname}/v1/providers/x/y/versions")
      .with(headers: { "Authorization" => "Bearer #{token}" })
  end

  it "fetches module versions", :vcr do
    response = client.all_module_versions(identifier: "hashicorp/consul/aws")
    expect(response.max).to eq(Gem::Version.new("0.10.1"))
  end

  it "fetches module versions from a custom registry" do
    hostname = "app.terraform.io"
    stub_request(:get, "https://#{hostname}/.well-known/terraform.json")
      .and_return(status: 200, body: {
        "modules.v1": "/api/registry/v1/modules/",
        "motd.v1": "/api/terraform/motd",
        "state.v2": "/api/v2/",
        "tfe.v2": "/api/v2/",
        "tfe.v2.1": "/api/v2/",
        "tfe.v2.2": "/api/v2/",
        "versions.v1": "https://checkpoint-api.hashicorp.com/v1/versions/"
      }.to_json)
    stub_request(:get, "https://#{hostname}/api/registry/v1/modules/hashicorp/consul/aws/versions")
      .and_return(status: 200, body: {
        modules: [
          {
            source: "hashicorp/consul/aws",
            versions: [{ version: "0.1.0" }, { version: "0.2.0" }]
          }
        ]
      }.to_json)
    client = described_class.new(hostname: hostname)
    response = client.all_module_versions(identifier: "hashicorp/consul/aws")
    expect(response).to contain_exactly(Gem::Version.new("0.1.0"), Gem::Version.new("0.2.0"))
  end

  it "raises an error when it cannot find the dependency", :vcr do
    expect do
      client.all_module_versions(identifier: "does/not/exist")
    end.to raise_error(/Response from registry was 404/)
  end

  it "fetches the source for a module dependency", :vcr do
    source = client.source(dependency: module_dependency)

    expect(source).to be_a Dependabot::Source
    expect(source.url).to eq("https://github.com/hashicorp/terraform-aws-consul")
  end

  it "fetches the source for a provider dependency", :vcr do
    source = client.source(dependency: module_dependency)

    expect(source).to be_a Dependabot::Source
    expect(source.url).to eq("https://github.com/hashicorp/terraform-aws-consul")
  end

  it "handles sources that can't be found", :vcr do
    provider_dependency = Dependabot::Dependency.new(
      name: "dependabot/package",
      version: "0.9.3",
      package_manager: "terraform",
      previous_version: "0.1.0",
      requirements: [{
        requirement: "0.3.8",
        groups: [],
        file: "main.tf",
        source: {
          type: "registry",
          registry_hostname: "registry.dependabot.com",
          module_identifier: "dependabot/package"
        }
      }],
      previous_requirements: [{
        requirement: "0.1.0",
        groups: [],
        file: "main.tf",
        source: {
          type: "registry",
          registry_hostname: "registry.dependabot.com",
          module_identifier: "dependabot/package"
        }
      }]
    )

    source = client.source(dependency: provider_dependency)
    expect(source).to be_nil
  end

  it "fetches the source for a provider from a custom registry", :vcr do
    hostname = "terraform.example.org"
    client = described_class.new(hostname: hostname)
    source = client.source(dependency: Dependabot::Dependency.new(
      name: "hashicorp/ciscoasa",
      version: "1.2.0",
      package_manager: "terraform",
      requirements: [{
        requirement: "~> 1.2",
        groups: [],
        file: "main.tf",
        source: {
          type: "provider",
          registry_hostname: hostname,
          module_identifier: "hashicorp/ciscoasa"
        }
      }]
    ))

    expect(source).to be_a Dependabot::Source
    expect(source.url).to eq("https://github.com/hashicorp/terraform-provider-ciscoasa")
  end

  context "with a custom hostname" do
    subject(:client) { described_class.new(hostname: hostname) }

    let(:hostname) { "registry.example.org" }

    it "raises helpful error when request is not authenticated", :vcr do
      stub_request(:get, "https://#{hostname}/.well-known/terraform.json").and_return(status: 401)

      expect do
        client.all_module_versions(identifier: "corp/package")
      end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
    end
  end

  describe "#service_url_for" do
    let(:metadata) { "https://registry.terraform.io/.well-known/terraform.json" }

    context "when the metadata endpoint is not reachable" do
      it "raises an error" do
        stub_request(:get, metadata).and_return(status: 404)

        expect do
          client.service_url_for("modules.v1")
        end.to raise_error(/Host does not support required Terraform-native service/)
      end
    end

    context "when the metadata endpoint redirects to another url" do
      it "follows the redirect" do
        stub_request(:get, metadata)
          .and_return(status: 301, headers: { "Location" => "https://example.org/terraform.json" })

        stub_request(:get, "https://example.org/terraform.json")
          .and_return(body: { "modules.v1": "https://example.org/v1/modules/" }.to_json)

        expect(client.service_url_for("modules.v1")).to eql("https://example.org/v1/modules/")
      end
    end

    context "when the service url is an absolute path" do
      it "returns the absolute url" do
        stub_request(:get, metadata)
          .and_return(body: { "modules.v1": "https://registry.example.org/v1/modules/" }.to_json)

        expect(client.service_url_for("modules.v1")).to eql("https://registry.example.org/v1/modules/")
      end
    end

    context "when the service url is an absolute path with a custom https port" do
      it "returns the absolute url" do
        stub_request(:get, metadata)
          .and_return(body: { "modules.v1": "https://registry.example.org:4443/v1/modules/" }.to_json)

        expect(client.service_url_for("modules.v1")).to eql("https://registry.example.org:4443/v1/modules/")
      end
    end

    context "when the service url is an absolute path using plain HTTP" do
      it "raises an error" do
        stub_request(:get, metadata)
          .and_return(body: { "modules.v1": "http://registry.example.org/v1/modules/" }.to_json)

        expect { client.service_url_for("modules.v1") }.to raise_error(/Unsupported scheme provided/)
      end
    end

    context "when the service url is a relative path" do
      it "returns the absolute url" do
        stub_request(:get, metadata).and_return(body: { "modules.v1": "/v1/modules/" }.to_json)

        expect(client.service_url_for("modules.v1")).to eql("https://registry.terraform.io/v1/modules/")
      end
    end

    context "when the metadata endpoint is not reachable with Timeout error" do
      it "raises an error" do
        stub_request(:get, metadata).to_raise(Excon::Error::Timeout)

        expect do
          client.service_url_for("modules.v1")
        end.to raise_error(Dependabot::PrivateSourceBadResponse)
      end
    end

    context "when the service url is not available" do
      it "raises an error" do
        stub_request(:get, metadata).and_return(body: { "modules.v1": "/v1/modules/" }.to_json)

        expect do
          client.service_url_for("providers.v1")
        end.to raise_error(/Host does not support required Terraform-native service/)
      end
    end
  end

  describe "enhanced private registry functionality" do
    let(:private_hostname) { "private-registry.example.com" }
    let(:private_client) { described_class.new(hostname: private_hostname) }
    let(:logger) { instance_double("Logger") }

    before do
      allow(Dependabot).to receive(:logger).and_return(logger)
    end

    describe "#headers_for" do
      context "with private registry" do
        it "includes enhanced headers" do
          expect(logger).to receive(:info).with(
            "Private registry operation: authentication_setup for #{private_hostname} (has_token: false, token_length: 0)"
          )

          headers = private_client.send(:headers_for, private_hostname)
          expect(headers).to include("User-Agent" => "Dependabot-Terraform/#{Dependabot::VERSION}")
        end

        it "includes authentication token when available" do
          credentials = [{ "type" => "terraform_registry", "host" => private_hostname, "token" => "test-token" }]
          client_with_creds = described_class.new(hostname: private_hostname, credentials: credentials)

          expect(logger).to receive(:info).with(
            "Private registry operation: authentication_setup for #{private_hostname} (has_token: true, token_length: 10)"
          )

          headers = client_with_creds.send(:headers_for, private_hostname)
          expect(headers).to include("Authorization" => "Bearer test-token")
          expect(headers).to include("User-Agent" => "Dependabot-Terraform/#{Dependabot::VERSION}")
        end
      end

      context "with public registry" do
        it "does not include enhanced headers or logging" do
          expect(logger).not_to receive(:info)

          headers = client.send(:headers_for, "registry.terraform.io")
          expect(headers).not_to include("User-Agent")
        end
      end
    end

    describe "#validate_credentials_for_hostname" do
      context "with private registry" do
        it "logs credential validation for private registry without credentials" do
          expect(logger).to receive(:info).with(
            "Private registry operation: credential_validation for #{private_hostname} (has_credentials: false)"
          )

          result = private_client.send(:validate_credentials_for_hostname, private_hostname)
          expect(result).to be false
        end

        it "logs credential validation for private registry with credentials" do
          credentials = [{ "type" => "terraform_registry", "host" => private_hostname, "token" => "test-token" }]
          client_with_creds = described_class.new(hostname: private_hostname, credentials: credentials)

          expect(logger).to receive(:info).with(
            "Private registry operation: credential_validation for #{private_hostname} (has_credentials: true)"
          )

          result = client_with_creds.send(:validate_credentials_for_hostname, private_hostname)
          expect(result).to be true
        end
      end

      context "with public registry" do
        it "returns true without logging for public registry" do
          expect(logger).not_to receive(:info)

          result = client.send(:validate_credentials_for_hostname, "registry.terraform.io")
          expect(result).to be true
        end
      end
    end

    describe "#source with enhanced logging" do
      let(:private_dependency) do
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

      context "successful source resolution" do
        before do
          stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
            .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
          stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
            .to_return(status: 204, headers: { "X-Terraform-Get" => "git::https://github.com/company/terraform-vpc" })
        end

        it "logs source resolution operations" do
          expect(logger).to receive(:info).at_least(:once).with(/Private registry operation: .* for #{private_hostname}/)

          source = private_client.source(dependency: private_dependency)
          expect(source).to be_a(Dependabot::Source)
          expect(source.url).to eq("https://github.com/company/terraform-vpc")
        end
      end

      context "authentication failure" do
        before do
          stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
            .to_return(status: 200, body: { "modules.v1": "/v1/modules/" }.to_json)
          stub_request(:get, "https://#{private_hostname}/v1/modules/company/vpc/aws/1.0.0/download")
            .to_return(status: 401)
        end

        it "logs authentication errors" do
          expect(logger).to receive(:info).at_least(:once).with(/Private registry operation: .* for #{private_hostname}/)
          expect(logger).to receive(:warn).at_least(:once).with(/Private registry error: .* for #{private_hostname}/)

          expect do
            private_client.source(dependency: private_dependency)
          end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
        end
      end

      context "JSON parsing error" do
        before do
          stub_request(:get, "https://#{private_hostname}/.well-known/terraform.json")
            .to_return(status: 200, body: { "providers.v1": "/v1/providers/" }.to_json)

          # Mock a provider dependency that will cause JSON parsing
          provider_dependency = Dependabot::Dependency.new(
            name: "company/custom",
            version: "1.0.0",
            package_manager: "terraform",
            requirements: [{
              requirement: "1.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: private_hostname,
                module_identifier: "company/custom"
              }
            }]
          )

          stub_request(:get, "https://#{private_hostname}/v1/providers/company/custom/1.0.0")
            .to_return(status: 200, body: "invalid json")

          @provider_dependency = provider_dependency
        end

        it "logs JSON parsing errors and returns nil" do
          expect(logger).to receive(:info).at_least(:once).with(/Private registry operation: .* for #{private_hostname}/)
          expect(logger).to receive(:warn).at_least(:once).with(/Private registry error: .* for #{private_hostname}/)

          result = private_client.source(dependency: @provider_dependency)
          expect(result).to be_nil
        end
      end
    end
  end
end
