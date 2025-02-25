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
                 security_advisories:, package_name:, versions:)
    super(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories
    )
    @package_name = package_name
    @versions = versions
  end

  def package_details
    Dependabot::Package::PackageDetails.new(
      dependency: dependency,
      releases: @versions.map do |version|
        Dependabot::Package::PackageRelease.new(
          version: Dependabot::Version.new(version)
        )
      end
    )
  end
end

RSpec.describe Dependabot::Package::PackageLatestVersionFinder do
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
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

  let(:available_versions) { ["7.0.0", "6.1.4", "6.0.2", "6.0.0"] }

  let(:finder) do
    StubPackageLatestVersionFinder.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      package_name: dependency_name,
      versions: available_versions
    )
  end

  describe "#latest_version" do
    subject(:latest_version) { finder.latest_version }

    it { is_expected.to eq(Gem::Version.new("7.0.0")) }

    context "when all versions are ignored" do
      let(:ignored_versions) { ["7.0.0", "6.1.4", "6.0.2", "6.0.0"] }

      it { is_expected.to be_nil }
    end

    context "when versions contain prereleases" do
      let(:available_versions) { ["7.0.0", "6.1.4", "6.0.2", "6.0.0", "7.1.0-beta"] }

      it "ignores prerelease versions" do
        expect(subject).to eq(Gem::Version.new("7.0.0"))
      end

      context "when prereleases are allowed" do
        before do
          allow(finder).to receive(:wants_prerelease?).and_return(true)
        end

        it "selects the highest prerelease version" do
          expect(subject).to eq(Gem::Version.new("7.1.0-beta"))
        end
      end
    end
  end

  describe "#latest_version_with_no_unlock" do
    subject(:latest_version_with_no_unlock) { finder.latest_version_with_no_unlock }

    context "when no constraints are present" do
      it { is_expected.to eq(Gem::Version.new("7.0.0")) }
    end

    context "with an exact version requirement" do
      let(:dependency_requirements) do
        [{ file: "Gemfile", requirement: "=6.0.0", groups: [], source: nil }]
      end

      it { is_expected.to eq(Gem::Version.new("6.0.0")) }
    end

    context "with an upper bound restriction" do
      let(:dependency_requirements) do
        [{ file: "Gemfile", requirement: ">=6.0.0,<7.0.0", groups: [], source: nil }]
      end

      it { is_expected.to eq(Gem::Version.new("6.1.4")) }
    end

    context "when ignored versions affect the latest selection" do
      let(:ignored_versions) { ["7.0.0"] }

      it { is_expected.to eq(Gem::Version.new("6.1.4")) }
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

    it { is_expected.to eq(Gem::Version.new("6.0.2")) }

    context "when no non-vulnerable versions exist" do
      let(:available_versions) { ["6.0.0", "6.0.1"] }

      it { is_expected.to be_nil }
    end
  end

  describe "version filtering" do
    subject(:filtered_versions) { finder.send(:filter_ignored_versions, versions) }

    let(:versions) { [Gem::Version.new("7.0.0"), Gem::Version.new("6.1.4"), Gem::Version.new("6.0.2")] }

    context "when no ignored versions are specified" do
      let(:ignored_versions) { [] }

      it "returns all versions" do
        expect(filtered_versions).to eq(versions)
      end
    end

    context "when ignoring a specific version" do
      let(:ignored_versions) { ["7.0.0"] }

      it "removes the ignored version" do
        expect(filtered_versions).to eq([Gem::Version.new("6.1.4"), Gem::Version.new("6.0.2")])
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
    let(:available_versions) { [] }

    it "returns nil for all version checks" do
      expect(finder.latest_version).to be_nil
      expect(finder.latest_version_with_no_unlock).to be_nil
      expect(finder.lowest_security_fix_version).to be_nil
    end
  end
end
