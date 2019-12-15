# frozen_string_literal: true

require "spec_helper"
require "dependabot/sbt/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Sbt::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:directory) { "/" }
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with a basic buildfile" do
    before do
      stub_request(:get, File.join(url, "build.sbt?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_sbt_basic_buildfile.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "project?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "fetches the buildfile" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(build.sbt))
    end
  end

  context "with a project directory" do
    before do
      stub_request(:get, File.join(url, "build.sbt?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_sbt_basic_buildfile.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "project?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_sbt_basic_project_dir.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "project/plugins.sbt?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_sbt_project_plugins_sbt.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "project/Dependencies.scala?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture(
            "github",
            "contents_sbt_project_dependencies_scala.json"
          ),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches all .sbt and .scala files in project directory" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:path)).
        to match_array(
          %w(/build.sbt /project/plugins.sbt /project/Dependencies.scala)
        )

      dependencies_dot_scala =
        file_fetcher_instance.files.
        find { |f| f.name.include?("Dependencies.scala") }

      expect(dependencies_dot_scala.content).
        to include(
          "val rediscala = \"com.github.etaty\" %% \"rediscala\" % \"1.8.0\"\n"
        )
    end
  end
end
