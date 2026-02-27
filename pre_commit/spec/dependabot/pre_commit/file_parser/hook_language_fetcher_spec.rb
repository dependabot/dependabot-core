# typed: false
# frozen_string_literal: true

require "spec_helper"
require "base64"
require "octokit"
require "dependabot/pre_commit/file_parser"
require "dependabot/pre_commit/file_parser/hook_language_fetcher"

# Struct to mock GitHub API content response (Sawyer::Resource uses dynamic attributes)
GithubContentResponse = Struct.new(:content, keyword_init: true)

RSpec.describe Dependabot::PreCommit::FileParser::HookLanguageFetcher do
  let(:credentials) { [] }
  let(:fetcher) { described_class.new(credentials: credentials) }
  let(:octokit_client) { instance_double(Octokit::Client) }
  let(:github_client) { instance_double(Dependabot::Clients::GithubWithRetries) }

  def github_content(content)
    GithubContentResponse.new(content: Base64.encode64(content))
  end

  before do
    allow(fetcher).to receive(:github_client).and_return(github_client)
    allow(github_client).to receive(:method_missing) do |method_name, *args, &block|
      octokit_client.public_send(method_name, *args, &block)
    end
  end

  describe "#fetch_language" do
    let(:repo_url) { "https://github.com/psf/black" }
    let(:revision) { "24.1.1" }
    let(:hook_id) { "black" }

    context "when hooks file exists and contains the hook" do
      let(:hooks_yaml) do
        <<~YAML
          - id: black
            name: black
            language: python
            entry: black
          - id: black-jupyter
            name: black-jupyter
            language: python
            entry: black
        YAML
      end

      before do
        allow(octokit_client).to receive(:contents)
          .with("psf/black", hash_including(path: ".pre-commit-hooks.yaml", ref: "24.1.1"))
          .and_return(github_content(hooks_yaml))
      end

      it "returns the language for the hook" do
        language = fetcher.fetch_language(repo_url: repo_url, revision: revision, hook_id: hook_id)
        expect(language).to eq("python")
      end
    end

    context "when hooks file contains a different hook" do
      let(:hooks_yaml) do
        <<~YAML
          - id: eslint
            name: eslint
            language: node
            entry: eslint
        YAML
      end

      before do
        allow(octokit_client).to receive(:contents)
          .with("psf/black", hash_including(path: ".pre-commit-hooks.yaml", ref: "24.1.1"))
          .and_return(github_content(hooks_yaml))
      end

      it "returns nil for non-existent hook" do
        language = fetcher.fetch_language(repo_url: repo_url, revision: revision, hook_id: hook_id)
        expect(language).to be_nil
      end
    end

    context "when hooks file doesn't exist (404)" do
      before do
        allow(octokit_client).to receive(:contents)
          .with("psf/black", hash_including(path: ".pre-commit-hooks.yaml", ref: "24.1.1"))
          .and_raise(Octokit::NotFound)
      end

      it "returns nil" do
        language = fetcher.fetch_language(repo_url: repo_url, revision: revision, hook_id: hook_id)
        expect(language).to be_nil
      end
    end

    context "when hooks file is invalid YAML" do
      let(:invalid_yaml) { "this is: not: valid: yaml: [" }

      before do
        allow(octokit_client).to receive(:contents)
          .with("psf/black", hash_including(path: ".pre-commit-hooks.yaml", ref: "24.1.1"))
          .and_return(github_content(invalid_yaml))
      end

      it "returns nil" do
        language = fetcher.fetch_language(repo_url: repo_url, revision: revision, hook_id: hook_id)
        expect(language).to be_nil
      end
    end

    context "with node language hooks" do
      let(:repo_url) { "https://github.com/pre-commit/mirrors-eslint" }
      let(:revision) { "v8.56.0" }
      let(:hook_id) { "eslint" }
      let(:hooks_yaml) do
        <<~YAML
          - id: eslint
            name: eslint
            language: node
            entry: eslint
        YAML
      end

      before do
        allow(octokit_client).to receive(:contents)
          .with("pre-commit/mirrors-eslint", hash_including(path: ".pre-commit-hooks.yaml", ref: "v8.56.0"))
          .and_return(github_content(hooks_yaml))
      end

      it "returns the node language" do
        language = fetcher.fetch_language(repo_url: repo_url, revision: revision, hook_id: hook_id)
        expect(language).to eq("node")
      end
    end

    context "when result is cached" do
      let(:hooks_yaml) do
        <<~YAML
          - id: black
            name: black
            language: python
            entry: black
        YAML
      end

      before do
        allow(octokit_client).to receive(:contents)
          .with("psf/black", hash_including(path: ".pre-commit-hooks.yaml", ref: "24.1.1"))
          .and_return(github_content(hooks_yaml))
      end

      it "only fetches once for the same repo/revision" do
        fetcher.fetch_language(repo_url: repo_url, revision: revision, hook_id: hook_id)
        fetcher.fetch_language(repo_url: repo_url, revision: revision, hook_id: hook_id)
        fetcher.fetch_language(repo_url: repo_url, revision: revision, hook_id: "black-jupyter")

        expect(octokit_client).to have_received(:contents).once
      end
    end

    context "with non-GitHub URL" do
      let(:repo_url) { "https://gitlab.com/some/repo" }

      it "returns nil for non-GitHub repos" do
        # Non-GitHub repos would attempt git clone, which we don't mock here
        # So it should catch the error and return nil
        language = fetcher.fetch_language(repo_url: repo_url, revision: revision, hook_id: hook_id)
        expect(language).to be_nil
      end
    end
  end
end
