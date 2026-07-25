# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/package/release_cooldown_options"
require "dependabot/azure_pipelines/package/package_details_fetcher"
require "dependabot/azure_pipelines/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::AzurePipelines::UpdateChecker do
  subject(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: [],
      update_cooldown: update_cooldown
    )
  end

  let(:ignored_versions) { [] }
  let(:update_cooldown) { nil }
  let(:credentials) do
    [Dependabot::Credential.new(
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    )]
  end
  let(:dependency_files) do
    [Dependabot::DependencyFile.new(name: "azure-pipelines.yml", content: "steps:\n  - task: Maven@#{version}\n")]
  end
  let(:dependency) { build_dependency("Maven", version) }
  let(:version) { "3" }

  let(:api_url) { "https://api.github.com/repos/microsoft/azure-pipelines-tasks" }
  let(:raw_url) { "https://raw.githubusercontent.com/microsoft/azure-pipelines-tasks/v276/Tasks" }

  def build_dependency(name, version)
    Dependabot::Dependency.new(
      name: name,
      version: version,
      package_manager: "azure_pipelines",
      requirements: [{ requirement: version, file: "azure-pipelines.yml", source: nil, groups: [] }]
    )
  end

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

  it_behaves_like "an update checker"

  describe "#latest_version" do
    it "offers the newest major" do
      expect(checker.latest_version.to_s).to eq("4")
    end

    context "when the pipeline is already on the newest major" do
      let(:version) { "4" }

      # The newest release is 4.276.0. Comparing it whole would look like an update
      # and produce a pull request that changes `Maven@4` to `Maven@4`.
      it "does not mistake a newer minor for a new major" do
        expect(checker.latest_version.to_s).to eq("4")
        expect(checker).to be_up_to_date
      end
    end

    context "when the pipeline pins a full version" do
      let(:version) { "3.250.0" }

      it "offers the newest full version" do
        expect(checker.latest_version.to_s).to eq("4.276.0")
      end
    end

    context "with an ignore condition" do
      let(:ignored_versions) { [">= 4"] }

      it "offers the newest version that is not ignored" do
        expect(checker.latest_version.to_s).to eq("3")
      end
    end

    context "when the newest major is deprecated" do
      let(:dependency) { build_dependency("NodeTool", "0") }
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "azure-pipelines.yml", content: "steps:\n  - task: NodeTool@0\n")]
      end

      before do
        stub_request(:get, "#{raw_url}/NodeToolV0/task.json")
          .to_return(status: 200, body: fixture("github", "node_tool_v0_task.json"))
      end

      it "leaves a pipeline already on it alone rather than rewriting it" do
        expect(checker.latest_version.to_s).to eq("0")
        expect(checker).to be_up_to_date
      end
    end

    context "when the task is not one Microsoft ships" do
      let(:dependency) { build_dependency("SonarQubePrepare", "7") }
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "azure-pipelines.yml", content: "steps:\n  - task: SonarQubePrepare@7\n")]
      end

      it "offers nothing" do
        expect(checker.latest_version).to be_nil
      end
    end
  end

  describe "cooldown" do
    let(:update_cooldown) do
      Dependabot::Package::ReleaseCooldownOptions.new(default_days: 90)
    end

    before do
      { "2" => "2020-01-01T00:00:00Z", "3" => "2021-01-01T00:00:00Z", "4" => Time.now.utc.iso8601 }
        .each do |major, date|
          stub_request(:get, "#{api_url}/commits?path=Tasks/MavenV#{major}/task.json&per_page=1")
            .to_return(
              status: 200,
              body: JSON.dump([{ "commit" => { "committer" => { "date" => date } } }])
            )
        end
    end

    it "holds back a major that is still inside its cooldown window" do
      expect(checker.latest_version.to_s).to eq("3")
    end
  end

  describe "#updated_requirements" do
    it "rewrites the requirement to the offered version" do
      expect(checker.updated_requirements.map(&:to_h)).to eq(
        [{ file: "azure-pipelines.yml", requirement: "4", groups: [], source: nil }]
      )
    end

    context "when two files pin the same task at different precision" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Maven",
          version: "3",
          package_manager: "azure_pipelines",
          requirements: [
            { requirement: "3", file: "azure-pipelines.yml", source: nil, groups: [] },
            { requirement: "3.250.0", file: "ci/build.yml", source: nil, groups: [] }
          ]
        )
      end

      # Merging the two must not quietly turn the major-only pin into a full one.
      it "renders each requirement at the precision it was written with" do
        expect(checker.updated_requirements.map { |req| [req[:file], req[:requirement]] })
          .to eq([["azure-pipelines.yml", "4"], ["ci/build.yml", "4.276.0"]])
      end
    end

    context "when nothing is on offer" do
      let(:dependency) { build_dependency("SonarQubePrepare", "7") }

      it "leaves the requirement alone" do
        expect(checker.updated_requirements.map { |req| req[:requirement] }).to eq(["7"])
      end
    end
  end

  describe "#can_update?" do
    it "reports an available major bump" do
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
    end

    context "when the pipeline is already on the newest major" do
      let(:version) { "4" }

      it "reports nothing to do" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end
  end
end
