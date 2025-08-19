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
    let(:tag_with_detail) do
      Dependabot::GitTagWithDetail.new(
        tag: "1.2.0",
        release_date: release_date
      )
    end

    context "when tag has no release date" do
      let(:release_date) { nil }

      it "returns false" do
        expect(resolver.check_if_version_in_cooldown_period?(tag_with_detail)).to be false
      end
    end

    context "when tag has a release date" do
      let(:release_date) { (Time.now - (10 * 24 * 60 * 60)).iso8601 } # 10 days ago

      before do
        allow(resolver).to receive(:cooldown_days_for).and_return(30)
      end

      it "returns false if the release date is outside the cooldown period" do
        allow(resolver).to receive(:cooldown_days_for).and_return(5)
        expect(resolver.check_if_version_in_cooldown_period?(tag_with_detail)).to be false
      end
    end
  end

  describe "#cooldown_enabled?" do
    context "when cooldown_options is nil" do
      let(:cooldown_options) { nil }

      it "returns false" do
        expect(resolver.cooldown_enabled?).to be false
      end
    end

    context "when cooldown_options has positive days" do
      it "returns true when default_days is positive" do
        allow(cooldown_options).to receive_messages(
          default_days: 1,
          semver_major_days: 0,
          semver_minor_days: 0,
          semver_patch_days: 0
        )
        expect(resolver.cooldown_enabled?).to be true
      end

      it "returns true when semver_major_days is positive" do
        allow(cooldown_options).to receive_messages(
          default_days: 0,
          semver_major_days: 1,
          semver_minor_days: 0,
          semver_patch_days: 0
        )
        expect(resolver.cooldown_enabled?).to be true
      end
    end

    context "when all cooldown days are zero" do
      it "returns false" do
        allow(cooldown_options).to receive_messages(
          default_days: 0,
          semver_major_days: 0,
          semver_minor_days: 0,
          semver_patch_days: 0
        )
        expect(resolver.cooldown_enabled?).to be false
      end
    end
  end
end
