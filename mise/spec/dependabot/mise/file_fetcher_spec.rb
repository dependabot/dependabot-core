# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/mise/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Mise::FileFetcher do
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

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    it "returns true when mise.toml is present" do
      expect(described_class.required_files_in?(["mise.toml"])).to be(true)
    end

    it "returns false when mise.toml is absent" do
      expect(described_class.required_files_in?(["README.md"])).to be(false)
    end
  end

  describe ".required_files_message" do
    it "returns a helpful message" do
      expect(described_class.required_files_message).to eq("Repo must contain a mise.toml file.")
    end
  end
end
