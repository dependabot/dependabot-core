# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/azure_pipelines/package/azure_devops_organization"
require "dependabot/azure_pipelines/package/installed_extensions_client"

RSpec.describe Dependabot::AzurePipelines::Package::InstalledExtensionsClient do
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
  let(:installed_url) do
    "https://extmgmt.dev.azure.com/example/_apis/extensionmanagement/installedextensions?api-version=7.1-preview.1"
  end

  before do
    described_class.clear_cache!
    Dependabot::AzurePipelines::Package::ResourceAreaClient.clear_cache!
    area_url =
      "https://dev.azure.com/example/_apis/resourceareas/" \
      "#{Dependabot::AzurePipelines::Package::ResourceAreaClient::EXTENSION_MANAGEMENT_ID}" \
      "?api-version=#{Dependabot::AzurePipelines::Package::ResourceAreaClient::API_VERSION}"
    stub_request(:get, area_url)
      .to_return(status: 200, body: JSON.dump("locationUrl" => "https://extmgmt.dev.azure.com/example/"))
  end

  it "returns when the extension was last installed or updated" do
    stub_request(:get, installed_url).to_return(
      status: 200,
      body: JSON.dump(
        "value" => [{
          "publisherId" => "Publisher",
          "extensionId" => "Extension",
          "version" => "2.0.0",
          "lastPublished" => "2026-10-18T19:59:49.97Z",
          "installState" => { "flags" => "none", "lastUpdated" => "2026-10-18T20:00:27.287Z" }
        }]
      )
    )

    expect(client.installed_at("publisher.extension")).to eq(Time.parse("2026-10-18T20:00:27.287Z"))
    expect(client.installed_at("publisher.other")).to be_nil
  end

  it "lists the installed extensions once per organization" do
    stub_request(:get, installed_url).to_return(status: 200, body: JSON.dump("value" => []))

    client.installed_at("publisher.extension")
    described_class.new(organization: organization).installed_at("publisher.other")

    expect(WebMock).to have_requested(:get, installed_url).once
  end

  it "falls back to nothing when the credential may not read extensions" do
    stub_request(:get, installed_url).to_return(status: 401, body: "")

    expect(client.installed_at("publisher.extension")).to be_nil
  end

  it "falls back to nothing when turned away with a sign-in page" do
    stub_request(:get, installed_url)
      .to_return(status: 200, body: "<html>Sign in</html>", headers: { "Content-Type" => "text/html" })

    expect(client.installed_at("publisher.extension")).to be_nil
  end

  it "falls back to nothing when the response is malformed" do
    stub_request(:get, installed_url).to_return(status: 200, body: "not json")

    expect(client.installed_at("publisher.extension")).to be_nil
  end
end
