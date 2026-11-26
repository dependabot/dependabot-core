# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/azure_pipelines/package/azure_devops_organization"
require "dependabot/azure_pipelines/package/resource_area_client"

RSpec.describe Dependabot::AzurePipelines::Package::ResourceAreaClient do
  let(:organization) do
    Dependabot::AzurePipelines::Package::AzureDevOpsOrganization.from_credentials(
      [
        Dependabot::Credential.new(
          "type" => "azure_devops_organization",
          "url" => "https://dev.azure.com/example"
        )
      ]
    )
  end
  let(:client) { described_class.new(organization: organization) }
  let(:resource_url) do
    "https://dev.azure.com/example/_apis/resourceareas/#{described_class::DISTRIBUTED_TASKS_ID}" \
      "?api-version=#{described_class::API_VERSION}"
  end

  before { described_class.clear_cache! }

  describe "#distributed_tasks_url" do
    it "uses the anonymous resource-area mapping for the organization" do
      stub_request(:get, resource_url)
        .to_return(status: 200, body: JSON.dump("locationUrl" => "https://dev.azure.com/example/"))

      expect(client.distributed_tasks_url).to eq("https://dev.azure.com/example/")
      expect(WebMock).to(
        have_requested(:get, resource_url).with { |request| !request.headers.key?("Authorization") }
      )
    end

    it "rejects an unexpected host with an actionable diagnostic" do
      stub_request(:get, resource_url)
        .to_return(status: 200, body: JSON.dump("locationUrl" => "https://tasks.example.net/example/"))

      expect { client.distributed_tasks_url }
        .to raise_error(Dependabot::DependabotError, /tasks\.example\.net.*proxy allowlist/)
    end

    it "rejects a service URL for another organization without suggesting a host change" do
      stub_request(:get, resource_url)
        .to_return(status: 200, body: JSON.dump("locationUrl" => "https://dev.azure.com/another/"))

      expect { client.distributed_tasks_url }
        .to raise_error(Dependabot::DependabotError, /path does not match/) do |error|
          expect(error.message).not_to include("proxy allowlist")
        end
    end
  end

  describe "#extension_management_url" do
    it "resolves the extension-management host for the configured organization" do
      url =
        "https://dev.azure.com/example/_apis/resourceareas/#{described_class::EXTENSION_MANAGEMENT_ID}" \
        "?api-version=#{described_class::API_VERSION}"
      stub_request(:get, url)
        .to_return(status: 200, body: JSON.dump("locationUrl" => "https://extmgmt.dev.azure.com/example/"))

      expect(client.extension_management_url).to eq("https://extmgmt.dev.azure.com/example/")
    end
  end

  describe "#marketplace_url" do
    it "resolves the gallery from the global resource-area endpoint anonymously" do
      stub_request(:get, described_class::GLOBAL_RESOURCE_AREA_URL)
        .to_return(status: 200, body: JSON.dump("locationUrl" => "https://marketplace.visualstudio.com/"))

      expect(client.marketplace_url).to eq("https://marketplace.visualstudio.com/")
      expect(WebMock).to(
        have_requested(:get, described_class::GLOBAL_RESOURCE_AREA_URL)
          .with { |request| !request.headers.key?("Authorization") }
      )
    end
  end
end
