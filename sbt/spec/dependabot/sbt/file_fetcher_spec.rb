# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/sbt/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Sbt::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { github_url + "repos/example/repo/contents/" }
  let(:github_url) { "https://api.github.com/" }
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/repo",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
    allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_beta_ecosystems).and_return(true)
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    subject { described_class.required_files_in?(filenames) }

    context "with a build.sbt" do
      let(:filenames) { %w(build.sbt) }

      it { is_expected.to be true }
    end

    context "without a build.sbt" do
      let(:filenames) { %w(pom.xml) }

      it { is_expected.to be false }
    end
  end

  context "with a basic build.sbt" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_basic.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "build.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_build_file.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "project/plugins.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404)
      stub_request(:get, url + "project/build.properties?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404)
      # "project" is listed as a dir in contents but won't have build.sbt
      stub_request(:get, url + "project/build.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404)
    end

    it "fetches the build.sbt" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).to eq(%w(build.sbt))
    end
  end

  context "with build.sbt, plugins.sbt and build.properties" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_basic.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "build.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_build_file.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "project/plugins.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_plugins_file.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "project/build.properties?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_build_properties.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "project/build.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404)
    end

    it "fetches all three files" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(build.sbt project/plugins.sbt project/build.properties))
    end

    describe "#ecosystem_versions" do
      it "returns the SBT version from build.properties" do
        expect(file_fetcher_instance.ecosystem_versions).to eq(
          { package_managers: { "sbt" => "1.9.7" } }
        )
      end
    end
  end

  context "with subprojects" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_with_subprojects.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "build.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_build_file.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "project/plugins.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404)
      stub_request(:get, url + "project/build.properties?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_build_properties.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "core/build.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_sbt_subproject_build_file.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "web/build.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404)
      stub_request(:get, url + "project/build.sbt?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404)
    end

    it "fetches the root and subproject build.sbt files" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(build.sbt project/build.properties core/build.sbt))
    end
  end

  context "when beta ecosystems are not enabled" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_beta_ecosystems).and_return(false)
    end

    it "raises a DependencyFileNotFound error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
