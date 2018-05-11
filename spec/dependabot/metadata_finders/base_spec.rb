# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/source"
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
    [{
      "type" => "git",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  before { allow(finder).to receive(:source).and_return(source) }
  let(:source) do
    Dependabot::Source.new(
      host: "github",
      repo: "gocardless/#{dependency_name}"
    )
  end

  describe "#source_url" do
    subject { finder.source_url }

    it { is_expected.to eq("https://github.com/gocardless/business") }

    context "with a bitbucket source" do
      let(:source) do
        Dependabot::Source.new(
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
    let(:dummy_commits_finder) do
      instance_double(Dependabot::MetadataFinders::Base::CommitsFinder)
    end

    it "delegates to CommitsFinder (and caches the instance)" do
      expect(Dependabot::MetadataFinders::Base::CommitsFinder).
        to receive(:new).
        with(
          credentials: credentials,
          source: source,
          dependency: dependency
        ).once.and_return(dummy_commits_finder)
      expect(dummy_commits_finder).
        to receive(:commits_url).twice.
        and_return("https://example.com/commits")
      expect(finder.commits_url).to eq("https://example.com/commits")
      expect(finder.commits_url).to eq("https://example.com/commits")
    end
  end

  describe "#commits" do
    subject { finder.commits }
    let(:dummy_commits_finder) do
      instance_double(Dependabot::MetadataFinders::Base::CommitsFinder)
    end

    it "delegates to CommitsFinder (and caches the instance)" do
      expect(Dependabot::MetadataFinders::Base::CommitsFinder).
        to receive(:new).
        with(
          credentials: credentials,
          source: source,
          dependency: dependency
        ).once.and_return(dummy_commits_finder)
      expect(dummy_commits_finder).
        to receive(:commits).twice.
        and_return(%w(some commits))
      expect(finder.commits).to eq(%w(some commits))
      expect(finder.commits).to eq(%w(some commits))
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

  describe "#changelog_text" do
    subject { finder.changelog_text }
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
        to receive(:changelog_text).twice.
        and_return("Such changelog")
      expect(finder.changelog_text).to eq("Such changelog")
      expect(finder.changelog_text).to eq("Such changelog")
    end
  end

  describe "#upgrade_guide_url" do
    subject { finder.upgrade_guide_url }
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
        to receive(:upgrade_guide_url).twice.
        and_return("https://example.com/CHANGELOG.md")
      expect(finder.upgrade_guide_url).to eq("https://example.com/CHANGELOG.md")
      expect(finder.upgrade_guide_url).to eq("https://example.com/CHANGELOG.md")
    end
  end

  describe "#upgrade_guide_text" do
    subject { finder.upgrade_guide_text }
    let(:dummy_changelog_finder) do
      instance_double(Dependabot::MetadataFinders::Base::ChangelogFinder)
    end

    it "delegates to ReleaseFinder (and caches the instance)" do
      expect(Dependabot::MetadataFinders::Base::ChangelogFinder).
        to receive(:new).
        with(
          credentials: credentials,
          source: source,
          dependency: dependency
        ).once.and_return(dummy_changelog_finder)
      expect(dummy_changelog_finder).
        to receive(:upgrade_guide_text).twice.
        and_return("Some upgrade guide notes")
      expect(finder.upgrade_guide_text).to eq("Some upgrade guide notes")
      expect(finder.upgrade_guide_text).to eq("Some upgrade guide notes")
    end
  end

  describe "#releases_url" do
    subject { finder.releases_url }
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
        to receive(:releases_url).twice.
        and_return("https://example.com/RELEASES.md")
      expect(finder.releases_url).to eq("https://example.com/RELEASES.md")
      expect(finder.releases_url).to eq("https://example.com/RELEASES.md")
    end
  end

  describe "#releases_text" do
    subject { finder.releases_text }
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
        to receive(:releases_text).twice.
        and_return("Some release notes")
      expect(finder.releases_text).to eq("Some release notes")
      expect(finder.releases_text).to eq("Some release notes")
    end
  end
end
