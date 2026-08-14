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

  describe "#files" do
    context "with a workspace using a glob member pattern" do
      let(:repo_contents_path) { build_tmp_repo("deno/workspace") }
      let(:file_fetcher_instance) do
        described_class.new(
          source: source,
          credentials: credentials,
          repo_contents_path: repo_contents_path
        )
      end

      before do
        allow(file_fetcher_instance).to receive(:clone_repo_contents).and_return(repo_contents_path)
      end

      after do
        FileUtils.rm_rf(repo_contents_path)
      end

      it "fetches the root manifest, every member manifest, and the lockfile" do
        expect(file_fetcher_instance.files.map(&:name)).to contain_exactly(
          "deno.json",
          "packages/alpha/deno.json",
          "packages/beta/deno.json",
          "deno.lock"
        )
      end
    end

    context "with unsafe workspace member entries" do
      let(:repo_contents_path) { build_tmp_repo("deno/workspace_unsafe") }
      let(:file_fetcher_instance) do
        described_class.new(
          source: source,
          credentials: credentials,
          repo_contents_path: repo_contents_path
        )
      end

      before do
        allow(file_fetcher_instance).to receive(:clone_repo_contents).and_return(repo_contents_path)
      end

      after do
        FileUtils.rm_rf(repo_contents_path)
      end

      it "skips absolute and traversal member paths" do
        # Members "../escape" and "/etc" must not be fetched.
        expect(file_fetcher_instance.files.map(&:name)).to contain_exactly(
          "deno.json",
          "packages/alpha/deno.json"
        )
      end
    end
  end
end
