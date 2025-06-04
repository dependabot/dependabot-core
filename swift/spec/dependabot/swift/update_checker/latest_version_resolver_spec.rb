# typed: false
# frozen_string_literal: true

require "dependabot/swift/update_checker/latest_version_resolver"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"
require "dependabot/git_commit_checker"
require "dependabot/package/release_cooldown_options"
require "dependabot/swift/package/package_details_fetcher"

RSpec.describe Dependabot::Swift::UpdateChecker::LatestVersionResolver do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "patrick-zippenfenig/SwiftNetCDF",
      version: "v1.1.7",
      requirements: [],
      package_manager: "swift"
    )
  end

  let(:credentials) { [Dependabot::Credential.new(type: "git_source", token: "test-token")] }
  let(:git_commit_checker) do
    Dependabot::GitCommitChecker.new(
      dependency: dependency,
      credentials: credentials,
      ignored_versions: [],
      raise_on_ignored: false,
      consider_version_branches_pinned: true
    )
  end
  let(:package_details_fetcher) do
    Dependabot::Swift::Package::PackageDetailsFetcher.new(
      dependency: dependency,
      credentials: credentials,
      git_commit_checker: git_commit_checker
    )
  end
  let(:cooldown_options) do
    Dependabot::Package::ReleaseCooldownOptions.new(
      default_days: 30,
      semver_major_days: 60,
      semver_minor_days: 45,
      semver_patch_days: 15
    )
  end

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      cooldown_options: cooldown_options,
      git_commit_checker: git_commit_checker
    )
  end

  describe "#select_version_tags_in_cooldown_period" do
    let(:allowed_version_tags) do
      [
        {
          tag: "v1.0.0",
          version: "1.0.0",
          commit_sha: "abc123",
          tag_sha: "def456"
        },
        {
          tag: "v2.0.0",
          version: "2.0.0",
          commit_sha: "abc124",
          tag_sha: "def457"
        }
      ]
    end
    let(:latest_version_tag) do
      {
        tag: "v2.0.0",
        version: "2.0.0",
        commit_sha: "abc124",
        tag_sha: "def457"
      }
    end

    let(:git_tag_with_detail_one) { instance_double(tag: "v1.0.0", release_date: "2025-06-01") }
    let(:git_tag_with_detail_two) { instance_double(tag: "v1.1.0", release_date: "2025-06-03") }
    let(:git_tag_with_detail_three) { instance_double(tag: "v2.0.0", release_date: "2025-05-30") }

    before do
      allow(git_commit_checker).to receive_messages(
        allowed_version_tags: allowed_version_tags,
        latest_version_tag: latest_version_tag,
        local_tag_for_latest_version: allowed_version_tags.first[:tag]
      )
      allow(resolver).to receive(:select_version_tags_in_cooldown_period).and_return(["v1.1.0", "v2.0.0"])
                     .and_return([])
      allow(resolver).to receive(:check_if_version_in_cooldown_period?).and_return(false, true, true)
    end

    it "returns tags that are in the cooldown period" do
      result = resolver.select_version_tags_in_cooldown_period
      expect(result).to eq([])
    end
  end

  describe "#check_if_version_in_cooldown_period?" do
    it "returns true if the release date is within the cooldown period" do
      release_date = (Time.now - (10 * 24 * 60 * 60)).iso8601 # 10 days ago
      expect(resolver.check_if_version_in_cooldown_period?(release_date)).to be true
    end

    it "returns false if the release date is outside the cooldown period" do
      release_date = (Time.now - (100 * 24 * 60 * 60)).iso8601 # 100 days ago
      expect(resolver.check_if_version_in_cooldown_period?(release_date)).to be false
    end
  end

  describe "#release_date_to_seconds" do
    it "converts a valid release date string to seconds" do
      release_date = "2025-05-27T12:34:56Z"
      expect(resolver.release_date_to_seconds(release_date)).to eq(Time.parse(release_date).to_i)
    end
  end
end
