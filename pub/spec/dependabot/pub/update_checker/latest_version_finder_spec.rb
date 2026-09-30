# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pub/update_checker/latest_version_finder"
require "dependabot/pub/package/package_details_fetcher"
require "dependabot/pub/version"
require "dependabot/package/package_release"
require "dependabot/package/release_cooldown_options"
require "dependabot/update_checkers/cooldown_calculation"

require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Pub::UpdateChecker::LatestVersionFinder do
  subject(:latest_version_finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "pub"
    )
  end

  let(:dependency_files) do
    files = project_dependency_files(project)
    files.each do |file|
      if defined?(git_dir)
        file.content.gsub!("$GIT_DIR", git_dir)
        file.content.gsub!("$REF", dependency_version)
      end
    end
    files
  end

  let(:requirements) { [] }
  let(:dependency_name) { "lints" }
  let(:requirements_update_strategy) { nil }
  let(:dependency_version) { "0.1.0" }
  let(:project) { "can_update" }

  let(:credentials) { [] }

  describe "#current_report" do
    context "when the response is successful" do
      it "can fetch current report" do
        report = latest_version_finder.current_report

        expect(report).not_to be_nil

        expect(report["name"]).to eq(dependency_name)
        expect(report["version"]).to be_a(String)
        expect(report["latest"]).to be_a(String)
      end
    end

    context "with latest version" do
      it "fetches latest versions" do
        versions = latest_version_finder

        # version resolution is not deterministic and response may return empty value
        expect(versions.latest_version).to be_a(String).or be_nil
        expect(versions.latest_resolvable_version).to be_a(String).or be_nil
        expect(versions.latest_resolvable_version_with_no_unlock).to be_a(String).or be_nil
        expect(versions.latest_version_resolvable_with_full_unlock).to be_a(String).or be_nil
      end
    end
  end

  describe "cooldown filtering" do
    subject(:finder) do
      described_class.new(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: credentials,
        cooldown_options: cooldown_options
      )
    end

    let(:cooldown_options) do
      Dependabot::Package::ReleaseCooldownOptions.new(default_days: 90, include: [dependency_name])
    end

    let(:package_details_fetcher) do
      instance_double(Dependabot::Pub::Package::PackageDetailsFetcher)
    end

    let(:latest_version) { "2.0.0" }

    let(:package_releases) do
      [
        Dependabot::Package::PackageRelease.new(
          version: Dependabot::Pub::Version.new("1.0.0"),
          released_at: Time.now
        )
      ]
    end

    before do
      allow(Dependabot::Pub::Package::PackageDetailsFetcher).to receive(:new).and_return(package_details_fetcher)
      allow(package_details_fetcher).to receive_messages(
        report: [{ "name" => dependency_name, "version" => dependency_version, "latest" => latest_version }],
        package_details_metadata: package_releases
      )
    end

    context "when the candidate is absent from non-empty registry metadata" do
      it "lets the update through without flagging cooldown as unavailable" do
        expect(finder.latest_version).to eq("2.0.0")
        expect(
          Dependabot::UpdateCheckers::CooldownCalculation.cooldown_date_unavailable?(dependency)
        ).to be(false)
      end
    end

    context "when the registry lists other dated releases but not the candidate" do
      let(:package_releases) do
        [
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Pub::Version.new("1.5.0"),
            released_at: Time.now
          )
        ]
      end

      it "does not falsely flag cooldown as unavailable for a healthy date source" do
        expect(finder.latest_version).to eq("2.0.0")
        expect(
          Dependabot::UpdateCheckers::CooldownCalculation.cooldown_date_unavailable?(dependency)
        ).to be(false)
      end
    end

    context "when no registry metadata is available at all" do
      let(:package_releases) { [] }

      it "lets the update through and records that cooldown could not be applied" do
        expect(finder.latest_version).to eq("2.0.0")
        expect(
          Dependabot::UpdateCheckers::CooldownCalculation.cooldown_date_unavailable?(dependency)
        ).to be(true)
      end
    end

    context "when no metadata is available and the candidate is not an upgrade" do
      let(:latest_version) { dependency_version }
      let(:package_releases) { [] }

      it "does not flag cooldown as unavailable" do
        expect(finder.latest_version).to eq(dependency_version)
        expect(
          Dependabot::UpdateCheckers::CooldownCalculation.cooldown_date_unavailable?(dependency)
        ).to be(false)
      end
    end

    context "when no metadata is available and the candidate is ignored" do
      subject(:finder) do
        described_class.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: [">= 2.0.0"],
          cooldown_options: cooldown_options
        )
      end

      let(:package_releases) { [] }

      it "does not flag cooldown as unavailable for a version that would be discarded" do
        finder.latest_version
        expect(
          Dependabot::UpdateCheckers::CooldownCalculation.cooldown_date_unavailable?(dependency)
        ).to be(false)
      end
    end

    context "when a matching release is still within the cooldown window" do
      let(:package_releases) do
        [
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Pub::Version.new("2.0.0"),
            released_at: Time.now
          )
        ]
      end

      it "holds back the update to the current version" do
        expect(finder.latest_version).to eq(dependency_version)
      end
    end
  end
end
