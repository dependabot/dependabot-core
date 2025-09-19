# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/package/package_latest_version_finder"

# Define the stubbed PackageLatestVersionFinder
class StubPackageLatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
  def initialize(dependency:, dependency_files:, credentials:, ignored_versions:, raise_on_ignored:,
                 security_advisories:, package_name:, cooldown_options:, releases:)
    super(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      cooldown_options: cooldown_options
    )
    @package_name = package_name
    @releases = releases
  end

  def cooldown_enabled?
    !!@cooldown_options
  end

  def package_details
    Dependabot::Package::PackageDetails.new(
      dependency: dependency,
      releases: @releases.map do |release|
        version = Dependabot::Version.new(release.fetch(:version))
        released_at = release[:released_at] ? Time.parse(release[:released_at].to_s) : nil
        yanked = release.fetch(:yanked, false)
        yanked_reason = release.fetch(:yanked_reason, nil)
        downloads = release.fetch(:downloads, nil)
        url = release.fetch(:url, nil)
        package_type = release.fetch(:package_type, nil)
        language = if release[:language]
                     Dependabot::Package::PackageLanguage.new(
                       name: release[:language].fetch(:name, ""),
                       version: release[:language].fetch(:version, nil)&.then { |v| TestVersion.new(v) },
                       requirement: release[:language].fetch(:requirement, nil)&.then do |r|
                         TestRequirement.new(r)
                       end
                     )
                   end

        Dependabot::Package::PackageRelease.new(
          version: version,
          released_at: released_at,
          yanked: yanked,
          yanked_reason: yanked_reason,
          downloads: downloads,
          url: url,
          package_type: package_type,
          language: language
        )
      end
    )
  end
end

RSpec.describe Dependabot::Package::PackageLatestVersionFinder do
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:language_with_requirement) do
    {
      name: "dummy",
      version: "2.7.0",
      requirement: ">= 2.7.0"
    }
  end

  let(:language_no_requirement) do
    {
      name: "dummy",
      version: "2.7.0"
    }
  end

  let(:language_empty) do
    {}
  end

  let(:available_release_7_1_0) do # rubocop:disable Naming/VariableNumber
    {
      version: "7.1.0",
      released_at: "2023-01-01",
      yanked: true,
      yanked_reason: "security",
      downloads: 5,
      url: "https://example.com",
      package_type: "gem",
      language: language_with_requirement
    }
  end

  let(:available_release_7_2_0) do # rubocop:disable Naming/VariableNumber
    {
      version: "7.2.0",
      released_at: Time.now.strftime("%Y-%m-%d"),
      yanked: true,
      yanked_reason: "security",
      downloads: 5,
      url: "https://example.com",
      package_type: "gem",
      language: language_with_requirement
    }
  end

  let(:available_release_7_0_0_beta1) do
    {
      version: "7.0.0.beta1",
      released_at: "2023-01-01",
      yanked: false,
      yanked_reason: nil,
      downloads: 1,
      url: "https://example.com",
      package_type: "gem",
      language: language_with_requirement
    }
  end

  let(:available_release_7_0_0) do # rubocop:disable Naming/VariableNumber
    {
      version: "7.0.0",
      released_at: "2023-01-01",
      yanked: false,
      yanked_reason: nil,
      downloads: 1,
      url: "https://example.com",
      package_type: "gem",
      language: language_with_requirement
    }
  end

  let(:available_release_6_1_4) do # rubocop:disable Naming/VariableNumber
    {
      version: "6.1.4",
      released_at: "2022-01-01",
      yanked: false,
      yanked_reason: nil,
      downloads: 2,
      url: "https://example.com",
      package_type: "gem",
      language: language_no_requirement
    }
  end

  let(:available_release_6_0_2) do # rubocop:disable Naming/VariableNumber
    {
      version: "6.0.2",
      yanked: false,
      yanked_reason: nil,
      downloads: 3,
      url: "https://example.com",
      package_type: "gem",
      language: language_empty
    }
  end

  let(:cooldown_enabled) { true }

  let(:available_release_6_0_0) do # rubocop:disable Naming/VariableNumber
    {
      version: "6.0.0",
      released_at: "2020-01-01",
      yanked: false,
      yanked_reason: nil,
      downloads: 4,
      url: "https://example.com",
      package_type: "gem",
      language: language_with_requirement
    }
  end

  let(:available_release_6_0_1) do # rubocop:disable Naming/VariableNumber
    {
      version: "6.0.1",
      released_at: Time.now.strftime("%Y-%m-%d"),
      yanked: false,
      yanked_reason: nil,
      downloads: 4,
      url: "https://example.com",
      package_type: "gem"
    }
  end

  let(:available_releases) do
    [
      available_release_7_2_0,
      available_release_7_0_0,
      available_release_7_1_0,
      available_release_6_1_4,
      available_release_6_0_2,
      available_release_6_0_1,
      available_release_6_0_0
    ]
  end

  let(:cooldown_options) do
    Dependabot::Package::ReleaseCooldownOptions.new(
      default_days: 7,
      semver_major_days: 10,
      semver_minor_days: 5,
      semver_patch_days: 2
    )
  end

  let(:finder) do
    StubPackageLatestVersionFinder.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      package_name: dependency_name,
      releases: available_releases,
      cooldown_options: cooldown_options
    )
  end
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:dependency_files) { [gemfile] }
  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: <<~GEMFILE
        source "https://rubygems.org"
        gem "#{dependency_name}", ">= #{dependency_version}"
      GEMFILE
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "dummy"
    )
  end
  let(:dependency_name) { "rails" }
  let(:dependency_version) { "6.0.0" }
  let(:dependency_requirements) do
    [{
      file: "Gemfile",
      requirement: ">= #{dependency_version}",
      groups: [],
      source: nil
    }]
  end

  describe "#latest_version" do
    subject(:latest_version) { finder.latest_version }

    it { is_expected.to eq(TestVersion.new("7.0.0")) }

    context "when all supported versions are ignored" do
      let(:ignored_versions) { ["7.0.0", "6.1.4", "6.0.2", "6.0.0"] }

      it { is_expected.to be_nil }
    end

    context "when versions contain prereleases" do
      let(:available_releases) do
        [
          available_release_7_0_0,
          available_release_7_0_0_beta1,
          available_release_6_1_4,
          available_release_6_0_2,
          available_release_6_0_0
        ]
      end

      it "ignores prerelease versions" do
        expect(latest_version).to eq(TestVersion.new("7.0.0"))
      end

      context "when prereleases are allowed" do
        before do
          allow(finder).to receive(:wants_prerelease?).and_return(true)
        end

        it "selects the highest prerelease version" do
          expect(latest_version).to eq(TestVersion.new("7.0.0"))
        end
      end
    end
  end

  describe "#latest_version_with_no_unlock" do
    subject(:latest_version_with_no_unlock) { finder.latest_version_with_no_unlock }

    context "when no constraints are present" do
      it { is_expected.to eq(TestVersion.new("7.0.0")) }
    end

    context "with an exact version requirement" do
      let(:dependency_requirements) do
        [{ file: "Gemfile", requirement: "=6.0.2", groups: [], source: nil }]
      end

      it { is_expected.to eq(TestVersion.new("6.0.2")) }
    end

    context "with an upper bound restriction" do
      let(:dependency_requirements) do
        [{ file: "Gemfile", requirement: ">=6.0.0,<7.0.0", groups: [], source: nil }]
      end

      it { is_expected.to eq(TestVersion.new("6.1.4")) }
    end

    context "when ignored versions affect the latest selection" do
      let(:ignored_versions) { ["7.0.0"] }

      it { is_expected.to eq(TestVersion.new("6.1.4")) }
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { finder.lowest_security_fix_version }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "dummy",
          vulnerable_versions: ["<= 6.0.1"]
        )
      ]
    end

    it { is_expected.to eq(TestVersion.new("6.0.2")) }

    context "when no non-vulnerable versions exist" do
      let(:available_releases) do
        [available_release_6_0_0]
      end

      it { is_expected.to be_nil }
    end
  end

  describe "version filtering" do
    subject(:filtered_versions) { finder.send(:filter_ignored_versions, releases) }

    let(:r1) { Dependabot::Package::PackageRelease.new(version: TestVersion.new("7.0.0")) }
    let(:r2) { Dependabot::Package::PackageRelease.new(version: TestVersion.new("6.1.4")) }
    let(:r3) { Dependabot::Package::PackageRelease.new(version: TestVersion.new("6.0.2")) }
    let(:releases) { [r1, r2, r3] }

    context "when no ignored versions are specified" do
      let(:ignored_versions) { [] }

      it "returns all versions" do
        expect(filtered_versions).to eq(releases)
      end
    end

    context "when ignoring a specific version" do
      let(:ignored_versions) { ["7.0.0"] }

      it "removes the ignored version" do
        expect(filtered_versions).to eq([r2, r3])
      end
    end

    context "when ignoring all versions" do
      let(:ignored_versions) { ["7.0.0", "6.1.4", "6.0.2"] }

      it "returns an empty array" do
        expect(filtered_versions).to eq([])
      end
    end
  end

  describe "handling empty version lists" do
    let(:available_releases) { [] }

    it "returns nil for all version checks" do
      expect(finder.latest_version).to be_nil
      expect(finder.latest_version_with_no_unlock).to be_nil
      expect(finder.lowest_security_fix_version).to be_nil
    end
  end
end
