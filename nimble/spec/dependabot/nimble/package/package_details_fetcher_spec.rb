# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/nimble/package/package_details_fetcher"

RSpec.describe Dependabot::Nimble::Package::PackageDetailsFetcher do
  subject(:fetcher) { described_class.new(dependency: dependency, package_index: package_index) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "chronos",
      version: "4.0.4",
      package_manager: "nimble",
      requirements: [{ requirement: ">= 4.0.4", file: "example.nimble", groups: ["dependencies"], source: nil }]
    )
  end
  let(:package_index) { instance_double(Dependabot::Nimble::PackageIndex, repository_url: url) }
  let(:url) { "https://github.com/status-im/nim-chronos" }
  let(:checker) { instance_double(Dependabot::GitCommitChecker) }
  let(:released_at) { Time.utc(2026, 10, 1) }
  let(:releases) do
    %w(v4.0.4 v4.2.0 4.2.0).map do |tag|
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::Nimble::Version.new(tag), tag: tag, released_at: released_at
      )
    end
  end

  before do
    allow(Dependabot::GitCommitChecker).to receive(:new).and_return(checker)
    allow(checker).to receive(:allowed_version_tags_with_release_dates).and_return(releases)
  end

  it "lists the version tags of the repository the index names, once per version" do
    expect(fetcher.fetch.releases.map(&:tag)).to contain_exactly("v4.0.4", "v4.2.0")
  end

  it "keeps the release date of each tag" do
    expect(fetcher.fetch.releases.map(&:released_at)).to all(eq(released_at))
  end

  it "looks the tags up in a git dependency on that repository" do
    fetcher.fetch
    expect(Dependabot::GitCommitChecker).to have_received(:new) do |dependency:, credentials:|
      expect(dependency.source_details(allowed_types: ["git"])).to include(type: "git", url: url)
      expect(credentials).to eq([])
    end
  end

  context "when the index does not know the package" do
    let(:url) { nil }

    it "has no releases" do
      expect(fetcher.fetch.releases).to eq([])
    end
  end

  context "when the repository cannot be reached" do
    before do
      allow(checker).to receive(:allowed_version_tags_with_release_dates)
        .and_raise(Dependabot::GitDependenciesNotReachable, [url])
    end

    it "has no releases" do
      expect(fetcher.fetch.releases).to eq([])
    end
  end
end
