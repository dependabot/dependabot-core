# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/azure_pipelines/package/azure_devops_organization"
require "dependabot/azure_pipelines/package/organization_task_fetcher"

RSpec.describe Dependabot::AzurePipelines::Package::OrganizationTaskFetcher do
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
  let(:fetcher) { described_class.new(organization: organization) }
  let(:resource_area_id) do
    Dependabot::AzurePipelines::Package::ResourceAreaClient::DISTRIBUTED_TASKS_ID
  end
  let(:resource_url) do
    "https://dev.azure.com/example/_apis/resourceareas/#{resource_area_id}" \
      "?api-version=#{Dependabot::AzurePipelines::Package::ResourceAreaClient::API_VERSION}"
  end
  let(:tasks_url) do
    "https://dev.azure.com/example/_apis/distributedtask/tasks?allversions=true&api-version=7.1"
  end

  before do
    described_class.clear_cache!
    stub_request(:get, resource_url)
      .to_return(status: 200, body: JSON.dump("locationUrl" => "https://dev.azure.com/example/"))
  end

  it "returns organization task versions and skips test uploads" do
    stub_request(:get, tasks_url)
      .to_return(
        status: 200,
        body: JSON.dump(
          "value" => [
            {
              "id" => "task-guid",
              "name" => "PrivateTask",
              "version" => { "major" => 1, "minor" => 2, "patch" => 3 },
              "contributionIdentifier" => "publisher.extension.task",
              "contributionVersion" => "4.5.6"
            },
            {
              "id" => "test-guid",
              "name" => "TestTask",
              "version" => { "major" => 1, "minor" => 0, "patch" => 0, "isTest" => true }
            }
          ]
        )
      )

    tasks = fetcher.tasks

    expect(tasks.map(&:name)).to eq(["PrivateTask"])
    expect(tasks.first.version.to_s).to eq("1.2.3")
    expect(tasks.first.contribution_version).to eq("4.5.6")
    expect(WebMock).to(
      have_requested(:get, resource_url).with { |request| !request.headers.key?("Authorization") }
    )
    expect(WebMock).to(
      have_requested(:get, tasks_url).with { |request| !request.headers.key?("Authorization") }
    )
  end

  it "raises an authentication failure for Azure DevOps sign-in HTML" do
    stub_request(:get, tasks_url)
      .to_return(status: 200, body: "<html>Sign in</html>", headers: { "Content-Type" => "text/html" })

    expect { fetcher.tasks }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
  end

  it "raises with the service's explanation when the task listing keeps failing" do
    stub_request(:get, tasks_url).to_return(
      status: 500,
      body: JSON.dump("message" => "TF400898: An internal error occurred.", "typeKey" => "VssServiceException")
    )

    expect { fetcher.tasks }.to raise_error(Dependabot::DependabotError, /HTTP 500: TF400898/)
    expect(WebMock).to have_requested(:get, tasks_url).times(4)
  end

  it "asks Azure DevOps not to redirect to its sign-in page" do
    stub_request(:get, tasks_url).to_return(status: 200, body: JSON.dump("value" => []))

    fetcher.tasks

    expect(WebMock).to have_requested(:get, tasks_url).with(headers: { "X-TFS-FedAuthRedirect" => "Suppress" })
  end

  it "rejects a malformed task listing instead of treating it as empty" do
    stub_request(:get, tasks_url).to_return(status: 200, body: JSON.dump("value" => {}))

    expect { fetcher.tasks }.to raise_error(Dependabot::DependabotError, /Unexpected task listing/)
  end
end
