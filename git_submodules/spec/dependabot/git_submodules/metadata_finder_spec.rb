# typed: false
# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/git_submodules/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::GitSubmodules::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { "https://github.com/example/manifesto.git" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "manifesto",
      version: "cd8274d15fa3ae2ab983129fb037999f264ba9a7",
      previous_version: "7638417db6d59f3c431d3e1f261cc637155684cd",
      requirements: [{
        file: ".gitmodules",
        requirement: nil,
        groups: [],
        source: { type: "git", url: url, branch: "master", ref: "master" }
      }],
      previous_requirements: [{
        file: ".gitmodules",
        requirement: nil,
        groups: [],
        source: { type: "git", url: url, branch: "master", ref: "master" }
      }],
      package_manager: "submodules"
    )
  end

  before do
    # Not hosted on GitHub Enterprise Server
    stub_request(:get, "https://example.com/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when the URL is a github one" do
      let(:url) { "https://github.com/example/manifesto.git" }

      it { is_expected.to eq("https://github.com/example/manifesto") }
    end

    context "when the URL is a bitbucket one" do
      let(:url) { "https://bitbucket.org/example/manifesto.git" }

      it { is_expected.to eq("https://bitbucket.org/example/manifesto") }
    end

    context "when the URL is an azure one" do
      let(:url) { "https://contoso@dev.azure.com/contoso/MyProject/_git/manifesto" }

      it { is_expected.to eq("https://dev.azure.com/contoso/MyProject/_git/manifesto") }
    end

    context "when the URL is from an unknown host" do
      let(:url) { "https://example.com/example/manifesto.git" }

      it { is_expected.to be_nil }
    end
  end

  describe "#commits_url" do
    subject(:commits_url) { finder.commits_url }

    context "when the URL is a github one" do
      let(:url) { "https://github.com/example/manifesto.git" }

      it do
        expect(commits_url)
          .to eq("https://github.com/example/manifesto/compare/" \
                 "7638417db6d59f3c431d3e1f261cc637155684cd..." \
                 "cd8274d15fa3ae2ab983129fb037999f264ba9a7")
      end
    end

    context "when the URL is a bitbucket one" do
      let(:url) { "https://bitbucket.org/example/manifesto.git" }

      it do
        expect(commits_url)
          .to eq("https://bitbucket.org/example/manifesto/branches/" \
                 "compare/cd8274d15fa3ae2ab983129fb037999f264ba9a7" \
                 "..7638417db6d59f3c431d3e1f261cc637155684cd")
      end
    end

    context "when the URL is an azure one" do
      let(:url) { "https://contoso@dev.azure.com/contoso/MyProject/_git/manifesto" }

      it do
        expect(commits_url)
          .to eq("https://dev.azure.com/contoso/MyProject/_git/manifesto/branchCompare" \
                 "?baseVersion=GC7638417db6d59f3c431d3e1f261cc637155684cd" \
                 "&targetVersion=GCcd8274d15fa3ae2ab983129fb037999f264ba9a7")
      end
    end

    context "when the URL is from an unknown host" do
      let(:url) { "https://example.com/example/manifesto.git" }

      it { is_expected.to be_nil }
    end
  end
end
