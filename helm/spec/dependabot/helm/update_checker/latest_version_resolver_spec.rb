# typed: false
# frozen_string_literal: true

require "dependabot/helm/update_checker/latest_version_resolver"
require "dependabot/helm/package/package_details_fetcher"
# rubocop:disable RSpec/SpecFilePathFormat
# rubocop:disable RSpec/FilePath
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

  let(:credentials) { [Dependabot::Credential.new(type: "git_source", token: "test-token")] }

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      cooldown_options: cooldown_options
    )
  end

  describe "#fetch_tag_and_release_date_helm_chart" do
    let(:versions) { [{ "version" => "1.0.0" }, { "version" => "1.1.0" }, { "version" => "2.0.0" }] }
    let(:repo_name) { "myrepo" }
    let(:chart_name) { "mychart" }

    before do
      allow(resolver).to receive(:select_tags_which_in_cooldown_from_chart).with(repo_name).and_return(["1.0.0"])
    end

    it "removes versions in cooldown" do
      filtered = resolver.fetch_tag_and_release_date_helm_chart(versions.dup, repo_name, chart_name)
      expect(filtered).to eq([{ "version" => "1.1.0" }, { "version" => "2.0.0" }])
    end
  end

  describe "#filter_versions_in_cooldown_period_using_oci" do
    let(:tags) { ["1.0.0", "1.1.0", "2.0.0", "2.1.0", "3.0.0"] }
    let(:recent_date) { (Time.now - (5 * 24 * 60 * 60)).iso8601 } # 5 days ago
    let(:old_date) { (Time.now - (90 * 24 * 60 * 60)).iso8601 } # 90 days ago

    let(:tags_with_release_date) do
      [
        Dependabot::GitTagWithDetail.new(tag: "1.0.0", release_date: old_date),
        Dependabot::GitTagWithDetail.new(tag: "1.1.0", release_date: old_date),
        Dependabot::GitTagWithDetail.new(tag: "2.0.0", release_date: recent_date), # In cooldown
        Dependabot::GitTagWithDetail.new(tag: "2.1.0", release_date: recent_date), # In cooldown
        Dependabot::GitTagWithDetail.new(tag: "3.0.0", release_date: old_date)
      ]
    end

    context "when there are tags in cooldown period" do
      before do
        allow(resolver).to receive(:select_tags_which_in_cooldown_using_oci)
          .with(tags_with_release_date)
          .and_return(["2.0.0", "2.1.0"])
      end

      it "removes tags that are in cooldown period" do
        result = resolver.filter_versions_in_cooldown_period_using_oci(tags.dup, tags_with_release_date)
        expect(result).to eq(["1.0.0", "1.1.0", "3.0.0"])
      end

      it "modifies the original array in place" do
        original_tags = tags.dup
        resolver.filter_versions_in_cooldown_period_using_oci(original_tags, tags_with_release_date)
        expect(original_tags).to eq(["1.0.0", "1.1.0", "3.0.0"])
      end
    end

    context "when no tags are in cooldown period" do
      before do
        allow(resolver).to receive(:select_tags_which_in_cooldown_using_oci)
          .with(tags_with_release_date)
          .and_return([])
      end

      it "returns all tags unchanged" do
        result = resolver.filter_versions_in_cooldown_period_using_oci(tags.dup, tags_with_release_date)
        expect(result).to eq(tags)
      end
    end

    context "when select_tags_which_in_cooldown_using_oci returns nil" do
      before do
        allow(resolver).to receive(:select_tags_which_in_cooldown_using_oci)
          .with(tags_with_release_date)
          .and_return(nil)
      end

      it "returns all tags unchanged" do
        result = resolver.filter_versions_in_cooldown_period_using_oci(tags.dup, tags_with_release_date)
        expect(result).to eq(tags)
      end
    end

    context "when tags array is empty" do
      let(:empty_tags) { [] }

      it "returns empty array" do
        result = resolver.filter_versions_in_cooldown_period_using_oci(empty_tags, tags_with_release_date)
        expect(result).to eq([])
      end
    end

    context "when tags_with_release_date is empty" do
      let(:empty_tags_with_release) { [] }

      before do
        allow(resolver).to receive(:select_tags_which_in_cooldown_using_oci)
          .with(empty_tags_with_release)
          .and_return([])
      end

      it "returns all tags unchanged" do
        result = resolver.filter_versions_in_cooldown_period_using_oci(tags.dup, empty_tags_with_release)
        expect(result).to eq(tags)
      end
    end

    context "when an error occurs" do
      before do
        allow(resolver).to receive(:select_tags_which_in_cooldown_using_oci)
          .and_raise(StandardError, "Test error")
        allow(Dependabot.logger).to receive(:error)
      end

      it "logs the error and returns original tags" do
        result = resolver.filter_versions_in_cooldown_period_using_oci(tags.dup, tags_with_release_date)

        expect(Dependabot.logger).to have_received(:error)
          .with("Error filter_versions_in_cooldown_period_for_oci:: Test error")
        expect(result).to eq(tags)
      end
    end
  end

  describe "#select_tags_which_in_cooldown_from_chart" do
    let(:repo_name) { "prometheus-community/helm-charts" }
    let(:git_tag_with_details) do
      [
        instance_double("GitTagWithDetail", tag: "v1.0.0", release_date: (Time.now - (10 * 24 * 60 * 60)).iso8601), # rubocop:disable RSpec/VerifiedDoubleReference
        instance_double("GitTagWithDetail", tag: "v1.1.0", release_date: (Time.now - (40 * 24 * 60 * 60)).iso8601) # rubocop:disable RSpec/VerifiedDoubleReference
      ]
    end

    before do
      allow(resolver.package_details_fetcher).to receive(:fetch_tag_and_release_date_from_chart)
        .with(repo_name).and_return(git_tag_with_details)
    end

    it "returns tags within the cooldown period" do
      result = resolver.select_tags_which_in_cooldown_from_chart(repo_name)
      expect(result).to eq(["v1.0.0"])
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
# rubocop:enable RSpec/SpecFilePathFormat
# rubocop:enable RSpec/FilePath
