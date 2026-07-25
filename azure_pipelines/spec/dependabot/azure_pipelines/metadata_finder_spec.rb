# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/azure_pipelines/metadata_finder"
require "dependabot/azure_pipelines/package/package_details_fetcher"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::AzurePipelines::MetadataFinder do
  subject(:finder) { described_class.new(dependency: dependency, credentials: credentials) }

  let(:credentials) do
    [Dependabot::Credential.new(
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    )]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: name,
      version: version,
      package_manager: "azure_pipelines",
      requirements: [{ requirement: version, file: "azure-pipelines.yml", source: nil, groups: [] }]
    )
  end
  let(:name) { "Maven" }
  let(:version) { "4" }

  let(:api_url) { "https://api.github.com/repos/microsoft/azure-pipelines-tasks" }
  let(:raw_url) { "https://raw.githubusercontent.com/microsoft/azure-pipelines-tasks/v276/Tasks" }

  before do
    Dependabot::AzurePipelines::Package::PackageDetailsFetcher.clear_cache!

    stub_request(:get, "#{api_url}/releases/latest")
      .to_return(status: 200, body: fixture("github", "releases_latest.json"))
    stub_request(:get, "#{api_url}/git/trees/v276:Tasks")
      .to_return(status: 200, body: fixture("github", "tasks_tree.json"))

    %w(2 3 4).each do |major|
      stub_request(:get, "#{raw_url}/MavenV#{major}/task.json")
        .to_return(status: 200, body: fixture("github", "maven_v#{major}_task.json"))
    end
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    it "points at the directory the task is developed in" do
      expect(finder.source_url)
        .to eq("https://github.com/microsoft/azure-pipelines-tasks/tree/HEAD/Tasks/MavenV4")
    end

    context "when the task is not one Microsoft ships" do
      let(:name) { "SonarQubePrepare" }
      let(:version) { "7" }

      it "offers no source" do
        expect(finder.source_url).to be_nil
      end
    end
  end
end
