# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/base"

RSpec.describe Dependabot::MetadataFinders::Base do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [
        { file: "Gemfile", requirement: ">= 0", groups: [], source: nil }
      ],
      previous_requirements: [
        { file: "Gemfile", requirement: ">= 0", groups: [], source: nil }
      ],
      previous_version: dependency_previous_version,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_previous_version) { "1.0.0" }
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end
  before { allow(finder).to receive(:source).and_return(source) }
  let(:source) do
    Dependabot::MetadataFinders::Base::Source.new(
      host: "github",
      repo: "gocardless/#{dependency_name}"
    )
  end

  describe "Source.from_url" do
    subject { described_class::Source.from_url(url) }

    context "with a GitHub URL" do
      let(:url) { "https://github.com/org/abc" }
      its(:host) { is_expected.to eq("github") }
      its(:repo) { is_expected.to eq("org/abc") }

      context "with a git protocol" do
        let(:url) { "git@github.com:org/abc" }
        its(:host) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
      end

      context "with a trailing .git" do
        let(:url) { "https://github.com/org/abc.git" }
        its(:host) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
      end
    end

    context "with a Bitbucket URL" do
      let(:url) { "https://bitbucket.org/org/abc" }
      its(:host) { is_expected.to eq("bitbucket") }
      its(:repo) { is_expected.to eq("org/abc") }
    end

    context "with a GitLab URL" do
      let(:url) { "https://gitlab.com/org/abc" }
      its(:host) { is_expected.to eq("gitlab") }
      its(:repo) { is_expected.to eq("org/abc") }
    end
  end

  describe "#source_url" do
    subject { finder.source_url }

    it { is_expected.to eq("https://github.com/gocardless/business") }

    context "with a bitbucket source" do
      let(:source) do
        Dependabot::MetadataFinders::Base::Source.new(
          host: "bitbucket",
          repo: "org/#{dependency_name}"
        )
      end

      it { is_expected.to eq("https://bitbucket.org/org/business") }
    end

    context "without a source" do
      let(:source) { nil }
      it { is_expected.to be_nil }
    end
  end

  describe "#commits_url" do
    subject { finder.commits_url }
    let(:dummy_commits_url_finder) do
      instance_double(Dependabot::MetadataFinders::Base::CommitsUrlFinder)
    end

    it "delegates to CommitsUrlFinder (and caches the instance)" do
      expect(Dependabot::MetadataFinders::Base::CommitsUrlFinder).
        to receive(:new).
        with(
          credentials: credentials,
          source: source,
          dependency: dependency
        ).once.and_return(dummy_commits_url_finder)
      expect(dummy_commits_url_finder).
        to receive(:commits_url).twice.
        and_return("https://example.com/commits")
      expect(finder.commits_url).to eq("https://example.com/commits")
      expect(finder.commits_url).to eq("https://example.com/commits")
    end
  end

  describe "#changelog_url" do
    subject { finder.changelog_url }
    let(:dummy_changelog_finder) do
      instance_double(Dependabot::MetadataFinders::Base::ChangelogFinder)
    end

    it "delegates to ChangelogFinder (and caches the instance)" do
      expect(Dependabot::MetadataFinders::Base::ChangelogFinder).
        to receive(:new).
        with(
          credentials: credentials,
          source: source,
          dependency: dependency
        ).once.and_return(dummy_changelog_finder)
      expect(dummy_changelog_finder).
        to receive(:changelog_url).twice.
        and_return("https://example.com/CHANGELOG.md")
      expect(finder.changelog_url).to eq("https://example.com/CHANGELOG.md")
      expect(finder.changelog_url).to eq("https://example.com/CHANGELOG.md")
    end
  end

  describe "#release_url" do
    subject { finder.release_url }
    let(:dummy_release_finder) do
      instance_double(Dependabot::MetadataFinders::Base::ReleaseFinder)
    end

    it "delegates to ReleaseFinder (and caches the instance)" do
      expect(Dependabot::MetadataFinders::Base::ReleaseFinder).
        to receive(:new).
        with(
          credentials: credentials,
          source: source,
          dependency: dependency
        ).once.and_return(dummy_release_finder)
      expect(dummy_release_finder).
        to receive(:release_url).twice.
        and_return("https://example.com/RELEASES.md")
      expect(finder.release_url).to eq("https://example.com/RELEASES.md")
      expect(finder.release_url).to eq("https://example.com/RELEASES.md")
    end
  end
end
