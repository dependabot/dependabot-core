# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/azure_pipelines/update_checker/latest_version_finder"

RSpec.describe Dependabot::AzurePipelines::UpdateChecker::LatestVersionFinder do
  before do
    stub_request(:get, "https://dev.azure.com/contoso/_apis/distributedtask/tasks?api-version=7.2-preview.1")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: fixture("http", "tasks.json"))

    stub_request(:get, "https://dev.azure.com/contoso/_apis/distributedtask/tasks/8d8eebd8-2b94-4c97-85af-839254cc6da4?allversions=true&api-version=7.2-preview.1")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: fixture("http", "tasks.json"))
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Gradle",
      version: "3.247.1",
      requirements: [],
      package_manager: "azure_pipelines"
    )
  end
  let(:ignored_versions) { [] }
  let(:credentials) { [] }

  describe "#latest_version" do
    subject(:latest_version) do
      described_class.new(
        dependency: dependency,
        ignored_versions: ignored_versions,
        credentials: credentials
      ).latest_version
    end

    it { is_expected.to eq(Dependabot::Version.new("4.252.1")) }

    context "when the user is on the latest version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Gradle",
          version: "4.252.1",
          requirements: [],
          package_manager: "azure_pipelines"
        )
      end

      it { is_expected.to eq(Dependabot::Version.new("4.252.1")) }
    end

    context "when the latest version is ignored" do
      let(:ignored_versions) { [">= 4.252.1"] }

      it { is_expected.to eq(Dependabot::Version.new("3.247.1")) }
    end

    context "when all newer versions are ignored" do
      let(:ignored_versions) { ["> 3.247.1"] }

      it { is_expected.to eq(Dependabot::Version.new("3.247.1")) }
    end

    context "when the dependency is not found" do
      before do
        stub_request(:get, "https://dev.azure.com/contoso/_apis/distributedtask/tasks?api-version=7.2-preview.1")
          .to_return(status: 200, body: "{\"count\": 0, \"value\": []}")
      end

      it { is_expected.to be_nil }
    end
  end
end
