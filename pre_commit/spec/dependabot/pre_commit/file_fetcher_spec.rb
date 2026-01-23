# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::PreCommit::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { "https://api.github.com/repos/example/repo/contents/" }
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
    Dependabot::Experiments.register(:enable_beta_ecosystems, true)
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    subject { described_class.required_files_in?(filenames) }

    context "with a .pre-commit-config.yaml file" do
      let(:filenames) { %w(.pre-commit-config.yaml README.md) }

      it { is_expected.to be(true) }
    end

    context "with a .pre-commit-config.yml file" do
      let(:filenames) { %w(.pre-commit-config.yml README.md) }

      it { is_expected.to be(true) }
    end

    context "with a .pre-commit.yaml file" do
      let(:filenames) { %w(.pre-commit.yaml README.md) }

      it { is_expected.to be(true) }
    end

    context "with a .pre-commit.yml file" do
      let(:filenames) { %w(.pre-commit.yml README.md) }

      it { is_expected.to be(true) }
    end

    context "with uppercase .Pre-Commit-Config.YAML file" do
      let(:filenames) { %w(.Pre-Commit-Config.YAML README.md) }

      it { is_expected.to be(true) }
    end

    context "without a pre-commit config file" do
      let(:filenames) { %w(README.md setup.py) }

      it { is_expected.to be(false) }
    end
  end

  describe ".required_files_message" do
    subject { described_class.required_files_message }

    it do
      is_expected.to eq(
        "Repo must contain a .pre-commit-config.yaml, .pre-commit-config.yml, " \
        ".pre-commit.yaml, or .pre-commit.yml file."
      )
    end
  end

  describe "#fetch_files" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "repo_contents.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + ".pre-commit-config.yaml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "pre_commit_config.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the .pre-commit-config.yaml file" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.first.name).to eq(".pre-commit-config.yaml")
      expect(file_fetcher_instance.files.first.type).to eq("file")
    end

    it "parses the file content correctly" do
      content = file_fetcher_instance.files.first.content
      expect(content).to include("repos:")
      expect(content).to include("pre-commit-hooks")
      expect(content).to include("v4.4.0")
    end

    context "when beta ecosystems are disabled" do
      before do
        Dependabot::Experiments.register(:enable_beta_ecosystems, false)
      end

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.message).to include("beta")
          end
      end
    end

    context "when the config file is missing" do
      before do
        stub_request(:get, url + ".pre-commit-config.yaml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404)
      end

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when exclude_paths is configured" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?).and_return(false)
        allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_beta_ecosystems).and_return(true)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enable_exclude_paths_subdirectory_manifest_files).and_return(true)
        file_fetcher_instance.exclude_paths = [".pre-commit-config.yaml"]
      end

      it "raises a DependencyFileNotFound error when all files are excluded" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.message).to include("No files found in")
          end
      end
    end

    context "with a .pre-commit-config.yml file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: [
              { "name" => ".pre-commit-config.yml", "path" => ".pre-commit-config.yml", "type" => "file" },
              { "name" => "README.md", "path" => "README.md", "type" => "file" }
            ].to_json,
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + ".pre-commit-config.yml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "name" => ".pre-commit-config.yml",
              "path" => ".pre-commit-config.yml",
              "content" => Base64.encode64("repos:\n  - repo: https://github.com/pre-commit/pre-commit-hooks\n"),
              "encoding" => "base64"
            }.to_json,
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the .pre-commit-config.yml file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.first.name).to eq(".pre-commit-config.yml")
      end
    end

    context "with a .pre-commit.yaml file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: [
              { "name" => ".pre-commit.yaml", "path" => ".pre-commit.yaml", "type" => "file" },
              { "name" => "README.md", "path" => "README.md", "type" => "file" }
            ].to_json,
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + ".pre-commit.yaml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "name" => ".pre-commit.yaml",
              "path" => ".pre-commit.yaml",
              "content" => Base64.encode64("repos:\n  - repo: https://github.com/pre-commit/pre-commit-hooks\n"),
              "encoding" => "base64"
            }.to_json,
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the .pre-commit.yaml file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.first.name).to eq(".pre-commit.yaml")
      end
    end

    context "with a .pre-commit.yml file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: [
              { "name" => ".pre-commit.yml", "path" => ".pre-commit.yml", "type" => "file" },
              { "name" => "README.md", "path" => "README.md", "type" => "file" }
            ].to_json,
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + ".pre-commit.yml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "name" => ".pre-commit.yml",
              "path" => ".pre-commit.yml",
              "content" => Base64.encode64("repos:\n  - repo: https://github.com/pre-commit/pre-commit-hooks\n"),
              "encoding" => "base64"
            }.to_json,
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the .pre-commit.yml file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.first.name).to eq(".pre-commit.yml")
      end
    end
  end

  describe "#ecosystem_versions" do
    it "returns nil" do
      expect(file_fetcher_instance.ecosystem_versions).to be_nil
    end
  end
end
