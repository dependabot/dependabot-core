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
    allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_beta_ecosystems).and_return(true)
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
        allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_beta_ecosystems).and_return(false)
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
  end

  describe "#ecosystem_versions" do
    it "returns nil" do
      expect(file_fetcher_instance.ecosystem_versions).to be_nil
    end
  end
end
