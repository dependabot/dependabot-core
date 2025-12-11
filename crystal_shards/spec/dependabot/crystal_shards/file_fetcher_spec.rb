# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/crystal_shards/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::CrystalShards::FileFetcher do
  let(:json_header) { { "content-type" => "application/json" } }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { "https://api.github.com/repos/example/project/contents/" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/project",
      directory: "/"
    )
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    subject { described_class.required_files_in?(filenames) }

    context "with a shard.yml file" do
      let(:filenames) { %w(shard.yml) }

      it { is_expected.to be(true) }
    end

    context "with shard.yml and shard.lock files" do
      let(:filenames) { %w(shard.yml shard.lock) }

      it { is_expected.to be(true) }
    end

    context "without a shard.yml file" do
      let(:filenames) { %w(README.md) }

      it { is_expected.to be(false) }
    end

    context "with only shard.lock file" do
      let(:filenames) { %w(shard.lock) }

      it { is_expected.to be(false) }
    end
  end

  describe ".required_files_message" do
    it "returns the correct message" do
      expect(described_class.required_files_message).to eq("Repo must contain a shard.yml")
    end
  end
end
