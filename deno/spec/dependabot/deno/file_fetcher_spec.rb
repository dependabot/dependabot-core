# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/file_fetcher"

RSpec.describe Dependabot::Deno::FileFetcher do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "test/repo",
      directory: "/"
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end

  before do
    allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(true)
  end

  describe ".required_files_in?" do
    it "returns true when deno.json is present" do
      expect(described_class.required_files_in?(%w(deno.json))).to be true
    end

    it "returns true when deno.jsonc is present" do
      expect(described_class.required_files_in?(%w(deno.jsonc))).to be true
    end

    it "returns false when neither is present" do
      expect(described_class.required_files_in?(%w(package.json))).to be false
    end
  end

  describe ".required_files_message" do
    it "returns a helpful message" do
      expect(described_class.required_files_message).to include("deno.json")
    end
  end
end
