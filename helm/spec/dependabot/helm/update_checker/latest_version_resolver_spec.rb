# typed: false
# frozen_string_literal: true

require "dependabot/helm/update_checker/latest_version_resolver"
require "dependabot/helm/package/package_details_fetcher"

RSpec.describe Dependabot::Helm::LatestVersionResolver do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "test-dependency",
      version: "v1.0.0",
      requirements: [],
      package_manager: "helm"
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
      cooldown_options: cooldown_options
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "test-dependency",
      version: "v1.0.0",
      requirements: [],
      package_manager: "helm"
    )
  end

  let(:credentials) { [Dependabot::Credential.new(type: "git_source", token: "test-token")] }

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      cooldown_options: cooldown_options
    )
  end

  describe "#filter_versions_in_cooldown_period_from_chart" do
    let(:versions) { ["v1.0.0", "v1.1.0", "v2.0.0"] }
    let(:repo_name) { "prometheus-community" }

    before do
      allow(resolver).to receive(:select_tags_which_in_cooldown_from_chart).with(repo_name).and_return(["v1.0.0"])
    end

    it "filters out versions in the cooldown period" do
      result = resolver.filter_versions_in_cooldown_period_from_chart(versions, repo_name)
      expect(result).to eq(["v1.0.0", "v1.1.0", "v2.0.0"])
    end
  end

  describe "#check_if_version_in_cooldown_period?" do
    let(:release_date) { (Time.now - (10 * 24 * 60 * 60)).iso8601 } # 10 days ago

    it "returns true if the release is within the cooldown period" do
      expect(resolver.check_if_version_in_cooldown_period?(release_date)).to be true
    end
  end

  describe "#select_tags_which_in_cooldown_from_chart" do
    let(:repo_name) { "prometheus-community/helm-charts" }
    let(:git_tag_with_details) do
      [
        instance_double("GitTagWithDetail", tag: "v1.0.0", release_date: (Time.now - (10 * 24 * 60 * 60)).iso8601), # 10 days ago
        instance_double("GitTagWithDetail", tag: "v1.1.0", release_date: (Time.now - (40 * 24 * 60 * 60)).iso8601) # 40 days ago
      ]
    end

    before do
      allow(resolver.package_details_fetcher).to receive(:fetch_tag_and_release_date_from_chart)
        .with(repo_name).and_return(git_tag_with_details)
    end

    it "returns tags within the cooldown period" do
      result = resolver.select_tags_which_in_cooldown_from_chart(repo_name)
      expect(result).to eq(["v1.0.0", "v1.1.0"])
    end

    it "logs an error if an exception occurs" do
      allow(resolver.package_details_fetcher).to receive(:fetch_tag_and_release_date_from_chart)
        .and_raise(StandardError, "Test error")
      expect(Dependabot.logger).to receive(:error).with(/Error checking if version is in cooldown: Test error/)
      result = resolver.select_tags_which_in_cooldown_from_chart(repo_name)
      expect(result).to eq([])
    end
  end

  describe "#release_date_to_seconds" do
    it "parses a valid release date into seconds" do
      release_date = "2023-01-01T00:00:00Z"
      expect(resolver.release_date_to_seconds(release_date)).to eq(Time.parse(release_date).to_i)
    end

    it "returns 0 for an invalid release date" do
      invalid_release_date = "invalid-date"
      expect(Dependabot.logger).to receive(:error).with(/Invalid release date format/)
      expect(resolver.release_date_to_seconds(invalid_release_date)).to eq(0)
    end
  end
end
