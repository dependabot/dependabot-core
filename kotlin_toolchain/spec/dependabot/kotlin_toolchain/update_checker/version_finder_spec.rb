# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/package/release_cooldown_options"
require "dependabot/security_advisory"
require "dependabot/kotlin_toolchain/requirement"
require "dependabot/kotlin_toolchain/update_checker/version_finder"

RSpec.describe Dependabot::KotlinToolchain::UpdateChecker::VersionFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: [],
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      raise_on_ignored: raise_on_ignored,
      cooldown_options: cooldown_options
    )
  end

  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }
  let(:cooldown_options) { nil }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "org.jetbrains.kotlin:kotlin-cli",
      version: current_version,
      requirements: [{
        file: "kotlin",
        requirement: current_version,
        groups: ["toolchain"],
        source: nil,
        metadata: nil
      }],
      package_manager: "kotlin_toolchain",
      metadata: { wrapper: true }
    )
  end
  let(:current_version) { "0.11.1" }
  let(:available_versions) do
    [
      { version: "0.11.1", source_url: "https://repo.example.test" },
      { version: "0.12.0-dev-4188", source_url: "https://repo.example.test" },
      { version: "0.12.0", source_url: "https://repo.example.test" }
    ]
  end
  let(:package_details_fetcher) do
    instance_double(
      Dependabot::KotlinToolchain::Package::PackageDetailsFetcher,
      fetch_available_versions: available_versions
    )
  end

  before do
    allow(Dependabot::KotlinToolchain::Package::PackageDetailsFetcher)
      .to receive(:new)
      .and_return(package_details_fetcher)
  end

  it "filters development builds for a stable wrapper" do
    expect(finder.latest_version_details.fetch(:version))
      .to eq(Dependabot::KotlinToolchain::Version.new("0.12.0"))
  end

  context "when the wrapper already follows development builds" do
    let(:current_version) { "0.12.0-dev-4187" }
    let(:available_versions) do
      [
        { version: "0.12.0-dev-4187", source_url: "https://repo.example.test" },
        { version: "0.12.0-dev-4188", source_url: "https://repo.example.test" }
      ]
    end

    it "selects the newest development build using Kotlin Toolchain ordering" do
      expect(finder.latest_version_details.fetch(:version))
        .to eq(Dependabot::KotlinToolchain::Version.new("0.12.0-dev-4188"))
    end
  end

  context "with ignored versions" do
    let(:ignored_versions) { [">= 0.12.0"] }

    it "keeps the newest version that is not ignored" do
      expect(finder.latest_version_details.fetch(:version))
        .to eq(Dependabot::KotlinToolchain::Version.new("0.11.1"))
    end
  end

  context "when every newer version is ignored" do
    let(:ignored_versions) { ["> 0.11.1"] }
    let(:raise_on_ignored) { true }

    it "raises so the update is reported as ignored" do
      expect { finder.latest_version_details }.to raise_error(Dependabot::AllVersionsIgnored)
    end
  end

  context "with a cooldown" do
    let(:cooldown_options) do
      Dependabot::Package::ReleaseCooldownOptions.new(
        default_days: 7,
        semver_major_days: 7,
        semver_minor_days: 7,
        semver_patch_days: 7,
        include: [],
        exclude: []
      )
    end
    let(:now) { Time.parse("2026-09-06T12:00:00Z") }
    let(:available_versions) do
      [
        { version: "0.11.1", source_url: "https://repo.example.test", released_at: now - (30 * 24 * 3600) },
        { version: "0.11.2", source_url: "https://repo.example.test", released_at: now - (10 * 24 * 3600) },
        { version: "0.12.0", source_url: "https://repo.example.test", released_at: now - (2 * 24 * 3600) }
      ]
    end

    before do
      allow(Time).to receive(:now).and_return(now)
      allow(package_details_fetcher).to receive(:fetch_release_metadata) { |release:| release }
    end

    it "skips versions released inside the cooldown window" do
      expect(finder.latest_version_details.fetch(:version))
        .to eq(Dependabot::KotlinToolchain::Version.new("0.11.2"))
    end

    context "when the release date is unknown" do
      let(:available_versions) do
        [
          { version: "0.11.1", source_url: "https://repo.example.test", released_at: now - (30 * 24 * 3600) },
          { version: "0.12.0", source_url: "https://repo.example.test" }
        ]
      end

      it "holds the version back until a date is known" do
        expect(finder.latest_version_details.fetch(:version))
          .to eq(Dependabot::KotlinToolchain::Version.new("0.11.1"))
      end
    end
  end

  context "with a security advisory" do
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: "org.jetbrains.kotlin:kotlin-cli",
          package_manager: "kotlin_toolchain",
          vulnerable_versions: ["< 0.12.0"]
        )
      ]
    end

    it "picks the lowest version that is not vulnerable" do
      expect(finder.lowest_security_fix_version_details.fetch(:version))
        .to eq(Dependabot::KotlinToolchain::Version.new("0.12.0"))
    end
  end
end
