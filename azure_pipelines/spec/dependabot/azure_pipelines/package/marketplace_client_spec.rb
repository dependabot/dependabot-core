# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/azure_pipelines/package/azure_devops_organization"
require "dependabot/azure_pipelines/package/marketplace_client"

RSpec.describe Dependabot::AzurePipelines::Package::MarketplaceClient do
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
    Dependabot::AzurePipelines::Package::ResourceAreaClient::GLOBAL_RESOURCE_AREA_URL
  end
  let(:query_url) { "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" }

  before do
    described_class.clear_cache!
    Dependabot::AzurePipelines::Package::ResourceAreaClient.clear_cache!
    stub_request(:get, resource_url)
      .to_return(status: 200, body: JSON.dump("locationUrl" => "https://marketplace.visualstudio.com/"))
  end

  it "returns the published date for the exact Marketplace version" do
    stub_request(:post, query_url)
      .with do |request|
        body = JSON.parse(request.body)
        body["filters"][0]["criteria"][0]["value"] == "publisher.extension" &&
          body["flags"] == 1 &&
          request.headers["Accept"] == "application/json;api-version=7.1-preview.1"
      end
      .to_return(
        status: 200,
        body: JSON.dump(
          "results" => [{
            "extensions" => [{
              "versions" => [
                { "version" => "1.2.3", "lastUpdated" => "2026-10-18T19:59:49.97Z" }
              ]
            }]
          }]
        )
      )

    expect(client.published_at("publisher.extension", "1.2.3"))
      .to eq(Time.parse("2026-10-18T19:59:49.97Z"))
  end

  it "does not send credentials directly from core" do
    stub_request(:post, query_url)
      .to_return(status: 200, body: JSON.dump("results" => [{ "extensions" => [{ "versions" => [] }] }]))

    client.published_at("publisher.extension", "1.2.3")

    expect(WebMock).to(
      have_requested(:post, query_url).with { |request| !request.headers.key?("Authorization") }
    )
  end

  it "raises an authentication failure instead of treating access denial as missing dates" do
    stub_request(:post, query_url).to_return(status: 403, body: "")

    expect { client.published_at("publisher.extension", "1.2.3") }
      .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
  end

  it "rejects malformed Marketplace responses" do
    stub_request(:post, query_url).to_return(status: 200, body: "not json")

    expect { client.published_at("publisher.extension", "1.2.3") }
      .to raise_error(Dependabot::DependabotError, /Could not parse/)
  end
end
