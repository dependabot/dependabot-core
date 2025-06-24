# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform/update_checker/latest_version_resolver"

RSpec.describe Dependabot::Terraform::UpdateChecker::LatestVersionResolver do
  let(:credentials) { [Dependabot::Credential.new(type: "git_source", token: "test-token")] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "patrick-zippenfenig/SwiftNetCDF",
      version: "v1.1.7",
      requirements: [],
      package_manager: "swift"
    )
  end
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

  describe "#filter_versions_in_cooldown_period_from_provider" do
    let(:versions) do
      [
        instance_double(Dependabot::Version, to_s: "v1.0.0"),
        instance_double(Dependabot::Version, to_s: "v0.9.0")
      ]
    end

    before do
      allow(resolver).to receive(:select_tags_which_in_cooldown_from_provider).and_return(["v0.9.0"])
    end

    it "filters out versions in cooldown period" do
      result = resolver.filter_versions_in_cooldown_period_from_provider(versions)
      expect(result.map(&:to_s)).to eq(["v1.0.0"])
    end

    it "returns all versions if an error occurs" do
      allow(resolver).to receive(:select_tags_which_in_cooldown_from_provider).and_raise(StandardError)
      result = resolver.filter_versions_in_cooldown_period_from_provider(versions)
      expect(result.map(&:to_s)).to eq(["v1.0.0", "v0.9.0"])
    end
  end

  describe "#filter_versions_in_cooldown_period_from_module" do
    let(:versions) do
      [
        instance_double(Dependabot::Version, to_s: "v1.0.0"),
        instance_double(Dependabot::Version, to_s: "v0.9.0")
      ]
    end

    before do
      allow(resolver).to receive(:select_tags_which_in_cooldown_from_module).and_return(["v0.9.0"])
    end

    it "filters out versions in cooldown period" do
      result = resolver.filter_versions_in_cooldown_period_from_module(versions)
      expect(result.map(&:to_s)).to eq(["v1.0.0"])
    end

    it "returns all versions if an error occurs" do
      allow(resolver).to receive(:select_tags_which_in_cooldown_from_module).and_raise(StandardError)
      result = resolver.filter_versions_in_cooldown_period_from_module(versions)
      expect(result.map(&:to_s)).to eq(["v1.0.0", "v0.9.0"])
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
end
