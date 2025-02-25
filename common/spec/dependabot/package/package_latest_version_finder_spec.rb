# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/package/package_latest_version_finder"

# Define the stubbed PackageLatestVersionFinder outside the RSpec block
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
      dependency: dependency, # ✅ Fix: Pass dependency
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
      package_manager: "bundler"
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

  # Define the available versions in the stub
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
  end

  describe "#latest_version_with_no_unlock" do
    subject(:latest_version_with_no_unlock) { finder.latest_version_with_no_unlock }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: version,
        requirements: requirements,
        package_manager: "bundler"
      )
    end
    let(:requirements) do
      [{ file: "Gemfile", requirement: req_string, groups: [], source: nil }]
    end

    context "with no requirement" do
      let(:req_string) { nil }
      let(:version) { nil }

      it { is_expected.to eq(Gem::Version.new("7.0.0")) }
    end

    context "with an equality string" do
      let(:req_string) { "=6.0.0" }
      let(:version) { "6.0.0" }

      it { is_expected.to eq(Gem::Version.new("6.0.0")) }
    end

    context "with a >= string" do
      let(:req_string) { ">=6.0.0" }
      let(:version) { nil }

      it { is_expected.to eq(Gem::Version.new("7.0.0")) }
    end

    context "with a full range string" do
      let(:req_string) { ">=6.0.0,<7.0.0" }
      let(:version) { nil }

      it { is_expected.to eq(Gem::Version.new("6.1.4")) }
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { finder.lowest_security_fix_version }

    let(:dependency_version) { "6.0.0" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "bundler",
          vulnerable_versions: ["<= 6.0.1"]
        )
      ]
    end

    it { is_expected.to eq(Gem::Version.new("6.0.2")) }
  end
end
