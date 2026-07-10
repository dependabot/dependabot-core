# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/julia/update_checker/latest_version_finder"
require "dependabot/julia/package/package_details_fetcher"

RSpec.describe Dependabot::Julia::LatestVersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: [],
      ignored_versions: [],
      security_advisories: [],
      raise_on_ignored: false,
      cooldown_config: cooldown_config
    )
  end

  let(:cooldown_config) { nil }
  let(:current_version) { "1.0.0" }
  let(:dependency_name) { "Example" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: [{
        file: "Project.toml",
        requirement: "1",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "julia",
      metadata: { julia_uuid: "7876af07-990d-54b4-ab0e-23690620f79a" }
    )
  end

  before do
    allow_any_instance_of(Dependabot::Julia::Package::PackageDetailsFetcher)
      .to receive(:fetch_package_releases)
      .and_return(
        available_versions.map do |v|
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Julia::Version.new(v),
            released_at: release_dates[v]
          )
        end
      )
  end

  let(:release_dates) { Hash.new(Time.now - (365 * 24 * 60 * 60)) }

  describe "#latest_version prerelease handling" do
    let(:available_versions) { %w(1.9.0 2.0.0-beta1) }

    it "does not select a prerelease for a dependency on a stable version" do
      expect(finder.latest_version).to eq(Dependabot::Julia::Version.new("1.9.0"))
    end

    context "when the dependency is already on a prerelease" do
      let(:current_version) { "2.0.0-alpha1" }

      it "selects the newer prerelease" do
        expect(finder.latest_version).to eq(Dependabot::Julia::Version.new("2.0.0-beta1"))
      end
    end

    context "when the dependency version is unknown" do
      let(:current_version) { nil }

      it "does not select a prerelease" do
        expect(finder.latest_version).to eq(Dependabot::Julia::Version.new("1.9.0"))
      end
    end
  end

  describe "cooldown include/exclude patterns" do
    let(:available_versions) { %w(1.5.0) }
    let(:release_dates) { { "1.5.0" => Time.now - (24 * 60 * 60) } }
    let(:cooldown_config) { { default_days: 7, include: [], exclude: exclude_patterns } }
    let(:exclude_patterns) { [] }

    context "with no exclusions" do
      it "applies the cooldown" do
        expect(finder.latest_version).to be_nil
      end
    end

    context "when the dependency is excluded by exact name" do
      let(:exclude_patterns) { ["Example"] }

      it "skips the cooldown" do
        expect(finder.latest_version).to eq(Dependabot::Julia::Version.new("1.5.0"))
      end
    end

    context "when the exclude pattern is a prefix of the name" do
      let(:dependency_name) { "ExampleExtra" }
      let(:exclude_patterns) { ["Example"] }

      it "does not treat the pattern as a substring match" do
        expect(finder.latest_version).to be_nil
      end
    end

    context "with a glob exclude pattern" do
      let(:dependency_name) { "ExampleExtra" }
      let(:exclude_patterns) { ["Example*"] }

      it "matches the glob" do
        expect(finder.latest_version).to eq(Dependabot::Julia::Version.new("1.5.0"))
      end
    end

    context "when the pattern contains regex metacharacters" do
      let(:dependency_name) { "ExampleXExtra" }
      let(:exclude_patterns) { ["Example.Extra"] }

      it "treats them literally" do
        expect(finder.latest_version).to be_nil
      end
    end
  end

  describe "#available_versions" do
    let(:available_versions) { %w(1.2.0 1.5.0 0.9.0) }

    it "returns versions above the current version in ascending order" do
      expect(finder.available_versions.map(&:to_s)).to eq(%w(1.2.0 1.5.0))
    end
  end
end
