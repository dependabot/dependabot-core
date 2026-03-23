# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Nix::FileFetcher do
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
    allow(file_fetcher_instance).to receive_messages(commit: "sha", allow_beta_ecosystems?: true)
  end

  describe ".required_files_in?" do
    it "returns true when both flake.nix and flake.lock are present" do
      expect(described_class.required_files_in?(%w(flake.nix flake.lock))).to be true
    end

    it "returns false when only flake.nix is present" do
      expect(described_class.required_files_in?(%w(flake.nix))).to be false
    end

    it "returns false when only flake.lock is present" do
      expect(described_class.required_files_in?(%w(flake.lock))).to be false
    end

    it "returns false when neither file is present" do
      expect(described_class.required_files_in?(%w(package.json))).to be false
    end
  end

  describe "#fetch_files" do
    before do
      stub_request(:get, url + "flake.nix?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture_body("flake.nix"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "flake.lock?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture_body("flake.lock"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches both flake.nix and flake.lock" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name)).to match_array(%w(flake.nix flake.lock))
    end

    context "when beta ecosystems are not allowed" do
      before do
        allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(false)
      end

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end

  private

  def fixture_body(filename)
    content = File.read(
      File.join(__dir__, "fixtures", filename)
    )
    {
      "name" => filename,
      "content" => Base64.encode64(content),
      "encoding" => "base64",
      "path" => filename
    }.to_json
  end
end
