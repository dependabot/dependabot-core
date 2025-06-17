# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dotnet_sdk/update_checker/latest_version_finder"

RSpec.describe Dependabot::DotnetSdk::UpdateChecker::LatestVersionFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      raise_on_ignored: raise_on_ignored
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "dotnet-sdk",
      version: "8.0.100",
      requirements: [],
      package_manager: "dotnet_sdk",
      metadata: metadata
    )
  end

  let(:dependency_files) { [] }
  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }
  let(:metadata) { {} }

  let(:mock_package_details_fetcher) { instance_double(Dependabot::DotnetSdk::Package::PackageDetailsFetcher) }
  let(:mock_package_details) { instance_double(Dependabot::Package::PackageDetails) }

  let(:available_releases) do
    [
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::DotnetSdk::Version.new("8.0.400"),
        released_at: Time.parse("2024-05-15")
      ),
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::DotnetSdk::Version.new("8.0.300"),
        released_at: Time.parse("2024-03-15")
      ),
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::DotnetSdk::Version.new("8.0.200"),
        released_at: Time.parse("2024-01-15")
      ),
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::DotnetSdk::Version.new("8.0.100"),
        released_at: Time.parse("2023-11-15")
      ),
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::DotnetSdk::Version.new("9.0.100-preview.1"),
        released_at: Time.parse("2024-06-01")
      )
    ]
  end

  before do
    allow(Dependabot::DotnetSdk::Package::PackageDetailsFetcher)
      .to receive(:new)
      .with(dependency: dependency)
      .and_return(mock_package_details_fetcher)

    allow(mock_package_details_fetcher)
      .to receive(:fetch)
      .and_return(mock_package_details)

    allow(mock_package_details)
      .to receive(:releases)
      .and_return(available_releases)
  end

  describe "#package_details" do
    it "returns package details from the fetcher" do
      expect(finder.package_details).to eq(mock_package_details)
    end

    it "calls the PackageDetailsFetcher with the correct dependency" do
      finder.package_details
      expect(Dependabot::DotnetSdk::Package::PackageDetailsFetcher)
        .to have_received(:new)
        .with(dependency: dependency)
    end

    it "memoizes the result" do
      2.times { finder.package_details }
      expect(mock_package_details_fetcher).to have_received(:fetch).once
    end
  end

  describe "#latest_version" do
    it "returns the latest stable version" do
      expect(finder.latest_version).to eq(Dependabot::DotnetSdk::Version.new("8.0.400"))
    end

    it "memoizes the result" do
      2.times { finder.latest_version }
      expect(mock_package_details_fetcher).to have_received(:fetch).once
    end

    context "when there are no releases" do
      let(:available_releases) { [] }

      it "returns nil" do
        expect(finder.latest_version).to be_nil
      end
    end

    context "when wants_prerelease? is true" do
      let(:metadata) { { allow_prerelease: true } }

      it "includes prerelease versions" do
        expect(finder.latest_version).to eq(Dependabot::DotnetSdk::Version.new("9.0.100-preview.1"))
      end
    end

    context "when wants_prerelease? is false" do
      let(:metadata) { { allow_prerelease: false } }

      it "excludes prerelease versions" do
        expect(finder.latest_version).to eq(Dependabot::DotnetSdk::Version.new("8.0.400"))
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { ["8.0.400"] }

      it "excludes ignored versions" do
        expect(finder.latest_version).to eq(Dependabot::DotnetSdk::Version.new("8.0.300"))
      end
    end

    context "with language_version parameter" do
      it "accepts the parameter and returns the latest version" do
        expect(finder.latest_version(language_version: "8.0")).to eq(Dependabot::DotnetSdk::Version.new("8.0.400"))
      end
    end
  end

  describe "#lowest_security_fix_version" do
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: "dotnet-sdk",
          package_manager: "dotnet_sdk",
          vulnerable_versions: ["<= 8.0.200"]
        )
      ]
    end

    it "returns the lowest version that fixes security vulnerabilities" do
      expect(finder.lowest_security_fix_version).to eq(Dependabot::DotnetSdk::Version.new("8.0.300"))
    end

    it "memoizes the result" do
      2.times { finder.lowest_security_fix_version }
      expect(mock_package_details_fetcher).to have_received(:fetch).once
    end

    context "when there are no security advisories" do
      let(:security_advisories) { [] }

      it "returns next stable version" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::DotnetSdk::Version.new("8.0.200"))
      end
    end

    context "when no versions fix the vulnerability" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "dotnet-sdk",
            package_manager: "dotnet_sdk",
            vulnerable_versions: [">= 1.0.0"]
          )
        ]
      end

      it "returns nil" do
        expect(finder.lowest_security_fix_version).to be_nil
      end
    end

    context "when current version is already secure" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "dotnet-sdk",
          version: "8.0.400",
          requirements: [],
          package_manager: "dotnet_sdk",
          metadata: metadata
        )
      end

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "dotnet-sdk",
            package_manager: "dotnet_sdk",
            vulnerable_versions: ["<= 8.0.200"]
          )
        ]
      end

      it "returns nil" do
        expect(finder.lowest_security_fix_version).to be_nil
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { ["8.0.300"] }

      it "excludes ignored versions from security fix" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::DotnetSdk::Version.new("8.0.400"))
      end
    end
  end

  describe "#wants_prerelease?" do
    context "when allow_prerelease is true in metadata" do
      let(:metadata) { { allow_prerelease: true } }

      it "returns true" do
        expect(finder.send(:wants_prerelease?)).to be true
      end
    end

    context "when allow_prerelease is false in metadata" do
      let(:metadata) { { allow_prerelease: false } }

      it "returns false" do
        expect(finder.send(:wants_prerelease?)).to be false
      end
    end

    context "when allow_prerelease is nil in metadata" do
      let(:metadata) { { allow_prerelease: nil } }

      it "returns false" do
        expect(finder.send(:wants_prerelease?)).to be false
      end
    end

    context "when metadata doesn't contain allow_prerelease" do
      let(:metadata) { {} }

      it "returns false" do
        expect(finder.send(:wants_prerelease?)).to be false
      end
    end

    context "when metadata is nil" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "dotnet-sdk",
          version: "8.0.100",
          requirements: [],
          package_manager: "dotnet_sdk"
          # No metadata provided
        )
      end

      it "returns false" do
        expect(finder.send(:wants_prerelease?)).to be false
      end
    end
  end

  describe "error handling" do
    context "when PackageDetailsFetcher raises an error" do
      before do
        allow(mock_package_details_fetcher)
          .to receive(:fetch)
          .and_raise(StandardError, "Network error")
      end

      it "propagates the error from package_details" do
        expect { finder.package_details }.to raise_error(StandardError, "Network error")
      end

      it "propagates the error from latest_version" do
        expect { finder.latest_version }.to raise_error(StandardError, "Network error")
      end

      it "propagates the error from lowest_security_fix_version" do
        expect { finder.lowest_security_fix_version }.to raise_error(StandardError, "Network error")
      end
    end

    context "when PackageDetailsFetcher returns nil" do
      before do
        allow(mock_package_details_fetcher)
          .to receive(:fetch)
          .and_return(nil)
      end

      it "handles nil package_details gracefully" do
        expect(finder.package_details).to be_nil
      end

      it "returns nil for latest_version when package_details is nil" do
        expect(finder.latest_version).to be_nil
      end

      it "returns nil for lowest_security_fix_version when package_details is nil" do
        expect(finder.lowest_security_fix_version).to be_nil
      end
    end
  end
end
