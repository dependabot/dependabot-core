# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/azure_pipelines/package/package_details_fetcher"

RSpec.describe Dependabot::AzurePipelines::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      fetch_release_dates: fetch_release_dates
    )
  end

  let(:fetch_release_dates) { false }
  let(:credentials) do
    [Dependabot::Credential.new(
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    )]
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
    described_class.clear_cache!

    stub_request(:get, "#{api_url}/releases/latest")
      .to_return(status: 200, body: fixture("github", "releases_latest.json"))
    stub_request(:get, "#{api_url}/git/trees/v276:Tasks")
      .to_return(status: 200, body: fixture("github", "tasks_tree.json"))

    %w(2 3 4).each do |major|
      stub_request(:get, "#{raw_url}/MavenV#{major}/task.json")
        .to_return(status: 200, body: fixture("github", "maven_v#{major}_task.json"))
    end
  end

  describe "#fetch" do
    it "returns a release for every major version of the task" do
      versions = fetcher.fetch.releases.map { |release| release.version.to_s }

      expect(versions).to contain_exactly("2", "3", "4")
    end

    it "truncates releases to the precision of the current pin" do
      release = fetcher.fetch.releases.max_by(&:version)

      expect(release.version.to_s).to eq("4")
      expect(release.details["task_version"]).to eq("4.276.0")
    end

    it "links each release to the directory it was resolved from" do
      release = fetcher.fetch.releases.max_by(&:version)

      expect(release.url)
        .to eq("https://github.com/microsoft/azure-pipelines-tasks/tree/v276/Tasks/MavenV4")
      expect(release.details["task_directory"]).to eq("MavenV4")
      expect(release.details["task_id"]).to eq("AC4EE482-65DA-4485-A532-7B085873E532")
    end

    context "when the task is pinned to a full version" do
      let(:version) { "3.250.0" }

      it "returns full versions rather than bare majors" do
        versions = fetcher.fetch.releases.map { |release| release.version.to_s }

        expect(versions).to contain_exactly("2.200.0", "3.250.1", "4.276.0")
      end
    end

    context "when the directory name does not match the task name" do
      let(:dependency) { build_dependency("Ant", "1") }

      before do
        stub_request(:get, "#{raw_url}/ANTV1/task.json")
          .to_return(status: 200, body: fixture("github", "ant_v1_task.json"))
      end

      it "resolves the task through the name declared in task.json" do
        expect(fetcher.fetch.releases.map { |release| release.version.to_s }).to eq(["1"])
      end
    end

    context "when task.json declares a different task than the directory suggests" do
      let(:dependency) { build_dependency("UseNode", "1") }

      before do
        stub_request(:get, "#{raw_url}/UseNodeV1/task.json")
          .to_return(status: 200, body: fixture("github", "node_tool_v0_task.json"))
      end

      it "rejects the mismatch rather than trusting the directory name" do
        expect(fetcher.fetch.releases).to be_empty
      end
    end

    context "when the task is deprecated" do
      let(:dependency) { build_dependency("NodeTool", "0") }

      before do
        stub_request(:get, "#{raw_url}/NodeToolV0/task.json")
          .to_return(status: 200, body: fixture("github", "node_tool_v0_task.json"))
      end

      it "flags the release as deprecated" do
        expect(fetcher.fetch.releases.first.details["deprecated"]).to be(true)
      end
    end

    context "when the task is referenced by GUID" do
      let(:dependency) { build_dependency("31c75bbb-bcdf-4706-8d7c-4da6a1959bc2", "0") }

      it "returns no releases rather than guessing" do
        expect(fetcher.fetch.releases).to be_empty
      end
    end

    context "when the task is not one Microsoft ships" do
      let(:dependency) { build_dependency("SonarQubePrepare", "7") }

      it "returns no releases" do
        expect(fetcher.fetch.releases).to be_empty
      end
    end

    context "when no release has been published" do
      before do
        stub_request(:get, "#{api_url}/releases/latest").to_return(status: 404, body: "{}")
        stub_request(:get, "#{api_url}/git/trees/master:Tasks")
          .to_return(status: 200, body: fixture("github", "tasks_tree.json"))
        %w(2 3 4).each do |major|
          stub_request(
            :get,
            "https://raw.githubusercontent.com/microsoft/azure-pipelines-tasks/master/Tasks/MavenV#{major}/task.json"
          ).to_return(status: 200, body: fixture("github", "maven_v#{major}_task.json"))
        end
      end

      it "falls back to the default branch" do
        expect(fetcher.fetch.releases.map { |release| release.version.to_s }).to contain_exactly("2", "3", "4")
      end
    end

    context "when the tasks listing cannot be read" do
      before do
        stub_request(:get, "#{api_url}/git/trees/v276:Tasks").to_return(status: 500, body: "")
      end

      it "returns no releases" do
        expect(fetcher.fetch.releases).to be_empty
      end
    end

    context "when a task.json is not valid JSON" do
      before do
        stub_request(:get, "#{raw_url}/MavenV4/task.json").to_return(status: 200, body: "not json")
      end

      it "skips that major and keeps the rest" do
        expect(fetcher.fetch.releases.map { |release| release.version.to_s }).to contain_exactly("2", "3")
      end
    end
  end

  describe "release dates" do
    let(:fetch_release_dates) { true }

    context "when the task is pinned to a major" do
      before do
        %w(2 3 4).each do |major|
          stub_request(:get, "#{api_url}/commits?path=Tasks/MavenV#{major}/task.json&per_page=1")
            .to_return(
              status: 200,
              body: fixture("github", "commits_first_page.json"),
              headers: {
                "Link" => "<#{api_url}/commits?path=Tasks/MavenV#{major}/task.json&per_page=1&page=38>; rel=\"last\""
              }
            )
          stub_request(:get, "#{api_url}/commits?path=Tasks/MavenV#{major}/task.json&per_page=1&page=38")
            .to_return(status: 200, body: fixture("github", "commits_last_page.json"))
        end
      end

      it "dates the release from when the major first shipped" do
        release = fetcher.fetch.releases.max_by(&:version)

        expect(release.released_at).to eq(Time.parse("2024-01-15T10:00:00Z"))
      end
    end

    context "when the task is pinned to a full version" do
      let(:version) { "3.250.0" }

      before do
        stub_request(:get, "#{api_url}/releases?per_page=100")
          .to_return(status: 200, body: fixture("github", "releases.json"))
      end

      it "dates the release from the sprint it shipped in" do
        release = fetcher.fetch.releases.max_by(&:version)

        expect(release.version.to_s).to eq("4.276.0")
        expect(release.released_at).to eq(Time.parse("2026-06-26T13:43:41Z"))
      end
    end

    context "when no cooldown is configured" do
      let(:fetch_release_dates) { false }

      it "does not spend requests establishing dates" do
        expect(fetcher.fetch.releases.filter_map(&:released_at)).to be_empty
      end
    end
  end

  describe "#task_directory" do
    it "returns the directory for the currently pinned major" do
      expect(fetcher.task_directory).to eq("MavenV3")
    end

    context "when the pinned major no longer exists" do
      let(:version) { "9" }

      it "falls back to a directory that does exist" do
        expect(fetcher.task_directory).to eq("MavenV2")
      end
    end
  end

  describe "caching" do
    it "looks the tasks listing up once per process" do
      fetcher.fetch
      described_class.new(dependency: dependency, credentials: credentials).fetch

      expect(WebMock).to have_requested(:get, "#{api_url}/git/trees/v276:Tasks").once
    end
  end
end
