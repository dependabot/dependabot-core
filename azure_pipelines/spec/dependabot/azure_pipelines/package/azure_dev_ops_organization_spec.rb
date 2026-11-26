# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/azure_pipelines/package/azure_devops_organization"

RSpec.describe Dependabot::AzurePipelines::Package::AzureDevOpsOrganization do
  describe ".from_credentials" do
    it "selects only the Azure DevOps organization registry type" do
      organization = described_class.from_credentials(
        [
          Dependabot::Credential.new("type" => "git_source", "url" => "https://dev.azure.com/other"),
          Dependabot::Credential.new(
            "type" => "azure_devops_organization",
            "url" => "https://dev.azure.com/example"
          )
        ]
      )

      expect(organization.url).to eq("https://dev.azure.com/example")
      expect(organization.organization).to eq("example")
    end

    it "does not infer an organization from Azure Repos credentials" do
      organization = described_class.from_credentials(
        [Dependabot::Credential.new("type" => "git_source", "url" => "https://dev.azure.com/example")]
      )

      expect(organization).to be_nil
    end

    it "rejects ambiguous organization registries" do
      credentials = %w(first second).map do |name|
        Dependabot::Credential.new(
          "type" => "azure_devops_organization",
          "url" => "https://dev.azure.com/#{name}"
        )
      end

      expect { described_class.from_credentials(credentials) }
        .to raise_error(Dependabot::DependabotError, /Only one/)
    end

    it "rejects non-HTTPS and nested organization URLs" do
      %w(http://dev.azure.com/example https://dev.azure.com/example/other).each do |url|
        expect do
          described_class.from_credentials(
            [Dependabot::Credential.new("type" => "azure_devops_organization", "url" => url)]
          )
        end.to raise_error(Dependabot::DependabotError, /valid HTTPS/)
      end
    end
  end

  describe "#headers" do
    it "does not expose registry secrets to the API client" do
      organization = described_class.from_credentials(
        [
          Dependabot::Credential.new(
            "type" => "azure_devops_organization",
            "url" => "https://dev.azure.com/example",
            "token" => "secret"
          )
        ]
      )

      expect(organization.headers).not_to have_key("Authorization")
    end
  end
end
