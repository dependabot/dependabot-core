# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"

require "dependabot/vcpkg/update_checker/latest_version_finder"
require "dependabot/vcpkg/package/package_details_fetcher"
require "dependabot/vcpkg/version"

RSpec.describe Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      cooldown_options: cooldown_options,
      raise_on_ignored: raise_on_ignored,
      options: options
    )
  end

  let(:dependency_name) { "baseline" }
  let(:dependency_version) { "2025.04.09" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        requirement: nil,
        groups: [],
        source: {
          type: "git",
          url: "https://github.com/microsoft/vcpkg.git",
          ref: dependency_version
        },
        file: "vcpkg.json"
      }],
      package_manager: "vcpkg"
    )
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "vcpkg.json",
        content: '{"name": "test", "version": "1.0.0", "builtin-baseline": "' + dependency_version + '"}',
        directory: "/"
      )
    ]
  end

  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:cooldown_options) { nil }
  let(:raise_on_ignored) { false }
  let(:options) { {} }

  describe "#package_details" do
    subject(:package_details) { finder.package_details }

    let(:package_details_fetcher) { instance_double(Dependabot::Vcpkg::Package::PackageDetailsFetcher) }
    let(:mock_package_details) do
      Dependabot::Package::PackageDetails.new(
        dependency: dependency,
        releases: [
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Vcpkg::Version.new("2025.06.13"),
            tag: "2025.06.13",
            url: "https://github.com/microsoft/vcpkg.git",
            released_at: Time.new(2025, 6, 13),
            details: { commit_sha: "abc123", tag_sha: "def456" }
          ),
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Vcpkg::Version.new("2025.04.09"),
            tag: "2025.04.09",
            url: "https://github.com/microsoft/vcpkg.git",
            released_at: Time.new(2025, 4, 9),
            details: { commit_sha: "ghi789", tag_sha: "jkl012" }
          )
        ]
      )
    end

    before do
      allow(Dependabot::Vcpkg::Package::PackageDetailsFetcher)
        .to receive(:new)
        .with(dependency: dependency)
        .and_return(package_details_fetcher)
      allow(package_details_fetcher).to receive(:fetch).and_return(mock_package_details)
    end

    it "fetches package details using PackageDetailsFetcher" do
      expect(package_details).to eq(mock_package_details)
      expect(Dependabot::Vcpkg::Package::PackageDetailsFetcher)
        .to have_received(:new).with(dependency: dependency)
      expect(package_details_fetcher).to have_received(:fetch)
    end

    it "memoizes the result" do
      2.times { finder.package_details }
      expect(package_details_fetcher).to have_received(:fetch).once
    end

    context "when PackageDetailsFetcher returns nil" do
      before do
        allow(package_details_fetcher).to receive(:fetch).and_return(nil)
      end

      it "returns nil" do
        expect(package_details).to be_nil
      end
    end
  end

  describe "#cooldown_enabled?" do
    subject(:cooldown_enabled) { finder.send(:cooldown_enabled?) }

    it "returns false by default" do
      expect(cooldown_enabled).to be(false)
    end

    context "when the experiment is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enable_cooldown_for_vcpkg).and_return(true)
      end

      it "returns true" do
        expect(cooldown_enabled).to be(true)
      end
    end
  end

  describe "inheritance" do
    it "inherits from PackageLatestVersionFinder" do
      expect(described_class.superclass).to eq(Dependabot::Package::PackageLatestVersionFinder)
    end
  end

  describe "#latest_version" do
    subject(:latest_version) { finder.latest_version }

    let(:package_details_fetcher) { instance_double(Dependabot::Vcpkg::Package::PackageDetailsFetcher) }
    let(:mock_package_details) do
      Dependabot::Package::PackageDetails.new(
        dependency: dependency,
        releases: [
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Vcpkg::Version.new("2025.06.13"),
            tag: "abc123",
            url: "https://github.com/microsoft/vcpkg.git",
            released_at: Time.new(2025, 6, 13),
            details: {}
          ),
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Vcpkg::Version.new("2025.04.09"),
            tag: "ghi789",
            url: "https://github.com/microsoft/vcpkg.git",
            released_at: Time.new(2025, 4, 9),
            details: {}
          )
        ]
      )
    end

    before do
      allow(Dependabot::Vcpkg::Package::PackageDetailsFetcher)
        .to receive(:new)
        .and_return(package_details_fetcher)
      allow(package_details_fetcher).to receive(:fetch).and_return(mock_package_details)
    end

    it "returns the latest version from package details" do
      expect(latest_version).to eq(Dependabot::Vcpkg::Version.new("2025.06.13"))
    end

    context "when no package details are available" do
      before do
        allow(package_details_fetcher).to receive(:fetch).and_return(nil)
      end

      it "returns nil" do
        expect(latest_version).to be_nil
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { [">= 2025.06.13"] }

      it "returns the latest non-ignored version" do
        expect(latest_version).to eq(Dependabot::Vcpkg::Version.new("2025.04.09"))
      end
    end
  end
end
