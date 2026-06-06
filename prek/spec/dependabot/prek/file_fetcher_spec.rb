# typed: false
# frozen_string_literal: true

require "base64"
require "spec_helper"
require "dependabot/prek/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Prek::FileFetcher do
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
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    subject { described_class.required_files_in?(filenames) }

    context "with a prek.toml file" do
      let(:filenames) { %w(prek.toml README.md) }

      it { is_expected.to be(true) }
    end

    context "with a .prek.toml file" do
      let(:filenames) { %w(.prek.toml README.md) }

      it { is_expected.to be(true) }
    end

    context "without a prek config file" do
      let(:filenames) { %w(.pre-commit-config.yaml README.md) }

      it { is_expected.to be(false) }
    end
  end

  describe ".required_files_message" do
    subject(:required_files_message) { described_class.required_files_message }

    it { is_expected.to eq("Repo must contain a prek.toml or .prek.toml file.") }
  end

  describe "#fetch_files" do
    def stub_listing(name)
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: [
            { "name" => name, "path" => name, "type" => "file" },
            { "name" => "README.md", "path" => "README.md", "type" => "file" }
          ].to_json,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "#{name}?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: {
            "name" => name,
            "path" => name,
            "content" => Base64.encode64(
              "[[repos]]\nrepo = \"https://github.com/pre-commit/pre-commit-hooks\"\nrev = \"v4.4.0\"\n"
            ),
            "encoding" => "base64"
          }.to_json,
          headers: { "content-type" => "application/json" }
        )
    end

    context "with a prek.toml file" do
      before { stub_listing("prek.toml") }

      it "fetches the prek.toml file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.first.name).to eq("prek.toml")
        expect(file_fetcher_instance.files.first.type).to eq("file")
      end

      it "fetches the file content" do
        content = file_fetcher_instance.files.first.content
        expect(content).to include("[[repos]]")
        expect(content).to include("v4.4.0")
      end
    end

    context "with a .prek.toml file" do
      before { stub_listing(".prek.toml") }

      it "fetches the .prek.toml file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.first.name).to eq(".prek.toml")
      end
    end

    context "when the config file is missing" do
      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: [{ "name" => "README.md", "path" => "README.md", "type" => "file" }].to_json,
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "prek.toml?ref=sha")
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
