# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/git/submodules"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Git::Submodules do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "manifesto",
      version: "sha2",
      previous_version: "sha1",
      requirements: [
        {
          file: ".gitmodules",
          requirement: nil,
          groups: [],
          source: { type: "git", url: url, branch: "master", ref: "master" }
        }
      ],
      package_manager: "submodules"
    )
  end
  let(:url) { "https://github.com/example/manifesto.git" }
  subject(:finder) do
    described_class.new(dependency: dependency, github_client: github_client)
  end
  let(:github_client) { Octokit::Client.new(access_token: "token") }

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
        is_expected.
          to eq("https://github.com/example/manifesto/compare/sha1...sha2")
      end
    end

    context "when the URL is a bitbucket one" do
      let(:url) { "https://bitbucket.org/example/manifesto.git" }
      it do
        is_expected.
          to eq("https://bitbucket.org/example/manifesto/branches/"\
                "compare/sha2..sha1")
      end
    end

    context "when the URL is from an unknown host" do
      let(:url) { "https://example.com/example/manifesto.git" }
      it { is_expected.to be_nil }
    end
  end
end
