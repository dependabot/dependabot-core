# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/update_checker/latest_version_resolver"
require "dependabot/dependency"
require "dependabot/credential"
require "dependabot/git_commit_checker"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Python::UpdateChecker::LatestVersionResolver do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "fastapi",
      version: "0.110.0",
      requirements: [{
        requirement: nil,
        file: "pyproject.toml",
        groups: ["dependencies"],
        source: {
          type: "git",
          url: "https://github.com/tiangolo/fastapi",
          ref: "0.110.0",
          branch: nil
        }
      }],
      package_manager: "pip"
    )
  end

  let(:credentials) { [Dependabot::Credential.new(type: "git_source", token: "test-token")] }
  let(:git_commit_checker) do
    Dependabot::GitCommitChecker.new(
      dependency: dependency,
      credentials: credentials,
      ignored_versions: [],
      raise_on_ignored: false
    )
  end

  let(:cooldown_options) { nil }

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      cooldown_options: cooldown_options,
      git_commit_checker: git_commit_checker
    )
  end

  let(:allowed_version_tags) do
    [
      { tag: "0.110.0", version: Gem::Version.new("0.110.0"), commit_sha: "abc1", tag_sha: "def1" },
      { tag: "0.111.0", version: Gem::Version.new("0.111.0"), commit_sha: "abc2", tag_sha: "def2" },
      { tag: "0.120.0", version: Gem::Version.new("0.120.0"), commit_sha: "abc3", tag_sha: "def3" },
      { tag: "0.124.0", version: Gem::Version.new("0.124.0"), commit_sha: "abc4", tag_sha: "def4" },
      { tag: "0.124.2", version: Gem::Version.new("0.124.2"), commit_sha: "abc5", tag_sha: "def5" },
      { tag: "0.125.0", version: Gem::Version.new("0.125.0"), commit_sha: "abc6", tag_sha: "def6" },
      { tag: "0.126.0", version: Gem::Version.new("0.126.0"), commit_sha: "abc7", tag_sha: "def7" },
      { tag: "0.127.0", version: Gem::Version.new("0.127.0"), commit_sha: "abc8", tag_sha: "def8" },
      { tag: "0.128.0", version: Gem::Version.new("0.128.0"), commit_sha: "abc9", tag_sha: "def9" }
    ]
  end

  let(:git_tag_details) do
    [
      Dependabot::GitTagWithDetail.new(tag: "0.110.0", release_date: "2025-02-01"),
      Dependabot::GitTagWithDetail.new(tag: "0.111.0", release_date: "2025-05-15"),
      Dependabot::GitTagWithDetail.new(tag: "0.120.0", release_date: "2025-10-01"),
      Dependabot::GitTagWithDetail.new(tag: "0.124.0", release_date: "2025-12-06"),
      Dependabot::GitTagWithDetail.new(tag: "0.124.2", release_date: "2025-12-10"),
      Dependabot::GitTagWithDetail.new(tag: "0.125.0", release_date: "2025-12-17"),
      Dependabot::GitTagWithDetail.new(tag: "0.126.0", release_date: "2025-12-20"),
      Dependabot::GitTagWithDetail.new(tag: "0.127.0", release_date: "2025-12-21"),
      Dependabot::GitTagWithDetail.new(tag: "0.128.0", release_date: "2025-12-27")
    ]
  end

  before do
    allow(git_commit_checker).to receive_messages(
      local_tags_for_allowed_versions: allowed_version_tags,
      local_tag_for_latest_version: allowed_version_tags.last,
      refs_for_tag_with_detail: git_tag_details
    )
    # Freeze time to January 21, 2026
    allow(Time).to receive(:now).and_return(Time.parse("2026-01-21"))
  end

  describe "#latest_version_tag" do
    subject(:latest_version_tag) { resolver.latest_version_tag }

    context "when cooldown is not set" do
      let(:cooldown_options) { nil }

      it "returns the latest version without filtering" do
        expect(latest_version_tag[:version]).to eq(Gem::Version.new("0.128.0"))
      end
    end

    context "when cooldown applies with 40-day default" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 40)
      end

      it "returns the latest version outside cooldown period" do
        # 0.128.0 released 2025-12-27 is 25 days old (in cooldown)
        # 0.124.2 released 2025-12-10 is 42 days old (outside cooldown)
        expect(latest_version_tag[:version]).to eq(Gem::Version.new("0.124.2"))
      end
    end

    context "when cooldown applies with 10-day default" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 10)
      end

      it "returns the latest version outside 10-day cooldown" do
        # 0.128.0 released 2025-12-27 is 25 days old (outside 10-day cooldown)
        expect(latest_version_tag[:version]).to eq(Gem::Version.new("0.128.0"))
      end
    end

    context "when all versions are in cooldown" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 365)
      end

      it "returns nil" do
        expect(latest_version_tag).to be_nil
      end
    end

    context "when cooldown has semver-based days" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 0,
          semver_major_days: 60,
          semver_minor_days: 40,
          semver_patch_days: 10
        )
      end

      it "applies semver-based cooldown correctly" do
        # Minor bump from 0.110.0 to 0.128.0 uses semver_minor_days: 40
        # 0.128.0 released 2025-12-27 is 25 days old (in cooldown with 40 days)
        # 0.124.2 released 2025-12-10 is 42 days old (outside cooldown with 40 days)
        expect(latest_version_tag[:version]).to eq(Gem::Version.new("0.124.2"))
      end
    end
  end

  describe "#cooldown_enabled?" do
    context "when cooldown_options is nil" do
      let(:cooldown_options) { nil }

      it "returns false" do
        expect(resolver.send(:cooldown_enabled?)).to be false
      end
    end

    context "when cooldown_options has positive default_days" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 10)
      end

      it "returns true" do
        expect(resolver.send(:cooldown_enabled?)).to be true
      end
    end

    context "when cooldown_options has positive semver_major_days" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 0,
          semver_major_days: 10
        )
      end

      it "returns true" do
        expect(resolver.send(:cooldown_enabled?)).to be true
      end
    end

    context "when cooldown_options has all zero days" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 0,
          semver_major_days: 0,
          semver_minor_days: 0,
          semver_patch_days: 0
        )
      end

      it "returns false" do
        expect(resolver.send(:cooldown_enabled?)).to be false
      end
    end
  end

  describe "#check_if_version_in_cooldown_period?" do
    let(:cooldown_options) do
      Dependabot::Package::ReleaseCooldownOptions.new(default_days: 30)
    end

    context "when tag has no release date" do
      let(:tag_with_detail) do
        Dependabot::GitTagWithDetail.new(tag: "0.128.0", release_date: nil)
      end

      it "returns false" do
        expect(resolver.send(:check_if_version_in_cooldown_period?, tag_with_detail)).to be false
      end
    end

    context "when release is within cooldown period" do
      let(:tag_with_detail) do
        Dependabot::GitTagWithDetail.new(tag: "0.128.0", release_date: "2026-01-10")
      end

      it "returns true" do
        # 11 days ago, cooldown is 30 days
        expect(resolver.send(:check_if_version_in_cooldown_period?, tag_with_detail)).to be true
      end
    end

    context "when release is outside cooldown period" do
      let(:tag_with_detail) do
        Dependabot::GitTagWithDetail.new(tag: "0.124.2", release_date: "2025-12-01")
      end

      it "returns false" do
        # 51 days ago, cooldown is 30 days
        expect(resolver.send(:check_if_version_in_cooldown_period?, tag_with_detail)).to be false
      end
    end
  end

  describe "#cooldown_days_for" do
    let(:cooldown_options) do
      Dependabot::Package::ReleaseCooldownOptions.new(
        default_days: 10,
        semver_major_days: 60,
        semver_minor_days: 40,
        semver_patch_days: 20
      )
    end

    it "returns semver_minor_days for minor version bump" do
      current = Dependabot::Python::Version.new("0.110.0")
      new_version = Dependabot::Python::Version.new("0.128.0")
      expect(resolver.send(:cooldown_days_for, current, new_version)).to eq(40)
    end

    it "returns semver_patch_days for patch version bump" do
      current = Dependabot::Python::Version.new("0.124.0")
      new_version = Dependabot::Python::Version.new("0.124.2")
      expect(resolver.send(:cooldown_days_for, current, new_version)).to eq(20)
    end

    it "returns semver_major_days for major version bump" do
      current = Dependabot::Python::Version.new("0.110.0")
      new_version = Dependabot::Python::Version.new("1.0.0")
      expect(resolver.send(:cooldown_days_for, current, new_version)).to eq(60)
    end

    it "returns default_days when current version is nil" do
      new_version = Dependabot::Python::Version.new("1.0.0")
      expect(resolver.send(:cooldown_days_for, nil, new_version)).to eq(10)
    end
  end
end
