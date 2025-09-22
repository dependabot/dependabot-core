# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/update_checker/latest_version_finder"
require "dependabot/rust_toolchain/package/package_details_fetcher"
require "dependabot/rust_toolchain/version"
require "dependabot/rust_toolchain/channel"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"

RSpec.describe Dependabot::RustToolchain::UpdateChecker::LatestVersionFinder do
  subject(:version_finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      raise_on_ignored: raise_on_ignored,
      cooldown_options: cooldown_options
    )
  end

  let(:dependency_files) { [rust_toolchain_file] }
  let(:rust_toolchain_file) do
    Dependabot::DependencyFile.new(
      name: "rust-toolchain.toml",
      content: rust_toolchain_content
    )
  end
  let(:rust_toolchain_content) do
    <<~TOML
      [toolchain]
      channel = "1.72"
    TOML
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "rust",
      version: dependency_version,
      requirements: [
        {
          file: "rust-toolchain.toml",
          requirement: dependency_requirement,
          groups: [],
          source: nil
        }
      ],
      package_manager: "rust_toolchain"
    )
  end
  let(:dependency_version) { "1.72" }
  let(:dependency_requirement) { "1.72" }

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
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }
  let(:cooldown_options) { nil }

  let(:package_details_fetcher) { instance_double(Dependabot::RustToolchain::Package::PackageDetailsFetcher) }
  let(:mock_versions) { [] }

  before do
    allow(Dependabot::RustToolchain::Package::PackageDetailsFetcher)
      .to receive(:new)
      .and_return(package_details_fetcher)
    allow(package_details_fetcher)
      .to receive(:fetch)
      .and_return(Dependabot::Package::PackageDetails.new(
                    dependency: dependency,
                    releases: mock_versions.map { |v| Dependabot::Package::PackageRelease.new(version: v) },
                    dist_tags: nil
                  ))
  end

  describe "#package_details" do
    let(:mock_versions) do
      [
        Dependabot::RustToolchain::Version.new("1.72.0"),
        Dependabot::RustToolchain::Version.new("1.72.1"),
        Dependabot::RustToolchain::Version.new("stable"),
        Dependabot::RustToolchain::Version.new("beta"),
        Dependabot::RustToolchain::Version.new("nightly")
      ]
    end

    it "returns package details with all available versions" do
      package_details = version_finder.package_details

      expect(package_details).to be_a(Dependabot::Package::PackageDetails)
      expect(package_details.dependency).to eq(dependency)
      expect(package_details.releases.map(&:version)).to match_array(mock_versions)
    end

    it "fetches versions from PackageDetailsFetcher" do
      version_finder.package_details

      expect(Dependabot::RustToolchain::Package::PackageDetailsFetcher)
        .to have_received(:new)
      expect(package_details_fetcher)
        .to have_received(:fetch)
    end
  end

  describe "#apply_post_fetch_latest_versions_filter" do
    let(:mock_versions) do
      [
        Dependabot::RustToolchain::Version.new("1.71.0"),
        Dependabot::RustToolchain::Version.new("1.72"),
        Dependabot::RustToolchain::Version.new("1.72.0"),
        Dependabot::RustToolchain::Version.new("1.72.1"),
        Dependabot::RustToolchain::Version.new("1.73.0"),
        Dependabot::RustToolchain::Version.new("stable"),
        Dependabot::RustToolchain::Version.new("beta"),
        Dependabot::RustToolchain::Version.new("nightly-2023-12-25")
      ]
    end

    context "when dependency requirement is a specific version with patch" do
      let(:dependency_requirement) { "1.72.0" }
      let(:dependency_version) { "1.72.0" }

      it "filters to versions matching the same channel type" do
        package_details = version_finder.package_details
        filtered_releases = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)

        expect(filtered_releases.map { |x| x.version.to_s })
          .to contain_exactly("1.71.0", "1.72.0", "1.72.1", "1.73.0")
      end
    end

    context "when dependency requirement is a major.minor version" do
      let(:dependency_requirement) { "1.72" }
      let(:dependency_version) { "1.72" }

      it "filters to versions matching the same channel type and converts to major.minor format" do
        package_details = version_finder.package_details
        filtered_releases = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)

        filtered_versions = filtered_releases.map { |x| x.version.to_s }
        expect(filtered_versions).to include("1.72")
        expect(filtered_versions).not_to include("stable", "beta", "nightly-2023-12-25", "1.72.0", "1.72.1")
      end
    end

    context "when dependency requirement is a channel" do
      let(:dependency_requirement) { "stable" }
      let(:dependency_version) { "stable" }

      it "returns no updates for channels" do
        package_details = version_finder.package_details
        filtered_releases = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)

        expect(filtered_releases.map { |x| x.version.to_s })
          .to be_empty
      end
    end

    context "when dependency requirement is a dated channel" do
      let(:dependency_requirement) { "nightly-2023-12-25" }
      let(:dependency_version) { "nightly-2023-12-25" }

      it "filters to versions matching channel type" do
        package_details = version_finder.package_details
        filtered_releases = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)

        expect(filtered_releases.map { |x| x.version.to_s })
          .to match_array(%w(nightly-2023-12-25))
      end
    end

    context "when dependency requirement is a nightly dated channel with mixed stability releases" do
      let(:dependency_requirement) { "nightly-2025-08-19" }
      let(:dependency_version) { "nightly-2025-08-19" }
      let(:mock_versions) do
        [
          Dependabot::RustToolchain::Version.new("nightly-2025-08-01"),
          Dependabot::RustToolchain::Version.new("nightly-2025-08-19"),
          Dependabot::RustToolchain::Version.new("nightly-2025-08-20"),
          Dependabot::RustToolchain::Version.new("stable-2025-08-07"),
          Dependabot::RustToolchain::Version.new("stable-2025-08-14"),
          Dependabot::RustToolchain::Version.new("beta-2025-08-10"),
          Dependabot::RustToolchain::Version.new("1.72.0")
        ]
      end

      it "only includes nightly releases, not stable or beta releases" do
        package_details = version_finder.package_details
        filtered_releases = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)

        expect(filtered_releases.map { |x| x.version.to_s })
          .to match_array(%w(nightly-2025-08-01 nightly-2025-08-19 nightly-2025-08-20))
        expect(filtered_releases.map { |x| x.version.to_s })
          .not_to include("stable-2025-08-07", "stable-2025-08-14", "beta-2025-08-10", "1.72.0")
      end
    end

    context "when dependency requirement is a stable dated channel with mixed stability releases" do
      let(:dependency_requirement) { "stable-2025-08-07" }
      let(:dependency_version) { "stable-2025-08-07" }
      let(:mock_versions) do
        [
          Dependabot::RustToolchain::Version.new("nightly-2025-08-01"),
          Dependabot::RustToolchain::Version.new("nightly-2025-08-19"),
          Dependabot::RustToolchain::Version.new("stable-2025-08-07"),
          Dependabot::RustToolchain::Version.new("stable-2025-08-14"),
          Dependabot::RustToolchain::Version.new("stable-2025-08-21"),
          Dependabot::RustToolchain::Version.new("beta-2025-08-10"),
          Dependabot::RustToolchain::Version.new("1.72.0")
        ]
      end

      it "only includes stable releases, not nightly or beta releases" do
        package_details = version_finder.package_details
        filtered_releases = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)

        expect(filtered_releases.map { |x| x.version.to_s })
          .to match_array(%w(stable-2025-08-07 stable-2025-08-14 stable-2025-08-21))
        expect(filtered_releases.map { |x| x.version.to_s })
          .not_to include("nightly-2025-08-01", "nightly-2025-08-19", "beta-2025-08-10", "1.72.0")
      end
    end
  end

  describe "#apply_post_fetch_lowest_security_fix_versions_filter" do
    let(:mock_versions) do
      [
        Dependabot::RustToolchain::Version.new("1.71.0"),
        Dependabot::RustToolchain::Version.new("1.72.0"),
        Dependabot::RustToolchain::Version.new("1.72.1"),
        Dependabot::RustToolchain::Version.new("stable"),
        Dependabot::RustToolchain::Version.new("beta")
      ]
    end

    it "applies the same filtering logic as latest versions filter" do
      package_details = version_finder.package_details

      latest_filtered = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)
      security_filtered = version_finder.send(
        :apply_post_fetch_lowest_security_fix_versions_filter,
        package_details.releases
      )

      expect(security_filtered.map { |x| x.version.to_s })
        .to match_array(latest_filtered.map { |x| x.version.to_s })
    end
  end

  describe "#filter_by_version_type" do
    let(:releases) do
      [
        create_release("1.71.0"),
        create_release("1.72"),
        create_release("1.72.0"),
        create_release("1.72.1"),
        create_release("1.73.0"),
        create_release("stable"),
        create_release("beta"),
        create_release("nightly-2023-12-25")
      ]
    end

    context "when dependency has a version type" do
      let(:dependency_requirement) { "1.72.0" }
      let(:dependency_version) { "1.72.0" }

      it "filters to only version releases" do
        filtered = version_finder.send(:filter_by_version_type, releases)

        expect(filtered.map { |x| x.version.to_s })
          .to contain_exactly("1.71.0", "1.72.0", "1.72.1", "1.73.0")
      end
    end

    context "when dependency has a channel type" do
      let(:dependency_requirement) { "stable" }
      let(:dependency_version) { "stable" }

      it "returns no updates for channels" do
        filtered = version_finder.send(:filter_by_version_type, releases)

        expect(filtered.map { |x| x.version.to_s })
          .to be_empty
      end
    end

    context "when dependency has major.minor format and releases have patch versions" do
      let(:dependency_requirement) { "1.72" }
      let(:dependency_version) { "1.72" }

      it "converts patch versions to major.minor format and deduplicates" do
        filtered = version_finder.send(:filter_by_version_type, releases)

        filtered_versions = filtered.map { |x| x.version.to_s }
        expect(filtered_versions).to include("1.72")
        expect(filtered_versions).not_to include("1.71.0", "1.72.0", "1.72.1", "1.73.0", "stable", "beta")

        # Verify deduplication - should only have one 1.72 entry
        expect(filtered_versions.count("1.72")).to eq(1)
      end
    end
  end

  describe "#major_minor_format?" do
    context "when version is in major.minor format" do
      it "returns true for version like '1.72'" do
        expect(version_finder.send(:major_minor_format?, "1.72")).to be(true)
      end

      it "returns true for version like '2.0'" do
        expect(version_finder.send(:major_minor_format?, "2.0")).to be(true)
      end
    end

    context "when version is in major.minor.patch format" do
      it "returns false for version like '1.72.0'" do
        expect(version_finder.send(:major_minor_format?, "1.72.0")).to be(false)
      end

      it "returns false for version like '1.72.1'" do
        expect(version_finder.send(:major_minor_format?, "1.72.1")).to be(false)
      end
    end

    context "when version is a channel" do
      it "returns false for 'stable'" do
        expect(version_finder.send(:major_minor_format?, "stable")).to be(false)
      end

      it "returns false for 'beta'" do
        expect(version_finder.send(:major_minor_format?, "beta")).to be(false)
      end

      it "returns false for dated channels" do
        expect(version_finder.send(:major_minor_format?, "nightly-2023-12-25")).to be(false)
      end
    end

    context "with edge cases" do
      it "returns false for single digit versions" do
        expect(version_finder.send(:major_minor_format?, "1")).to be(false)
      end

      it "returns false for empty or invalid versions" do
        expect(version_finder.send(:major_minor_format?, "invalid")).to be(false)
      end
    end
  end

  describe "integration scenarios" do
    context "when filtering mixed version types" do
      let(:mock_versions) do
        [
          Dependabot::RustToolchain::Version.new("1.71.0"),
          Dependabot::RustToolchain::Version.new("1.72"),
          Dependabot::RustToolchain::Version.new("1.72.0"),
          Dependabot::RustToolchain::Version.new("1.72.1"),
          Dependabot::RustToolchain::Version.new("1.72.2"),
          Dependabot::RustToolchain::Version.new("1.73.0"),
          Dependabot::RustToolchain::Version.new("stable"),
          Dependabot::RustToolchain::Version.new("beta"),
          Dependabot::RustToolchain::Version.new("nightly"),
          Dependabot::RustToolchain::Version.new("nightly-2023-12-25")
        ]
      end

      context "with major.minor dependency requirement" do
        let(:dependency_requirement) { "1.72" }
        let(:dependency_version) { "1.72" }

        it "properly filters versions" do
          package_details = version_finder.package_details
          filtered_releases = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)

          filtered_versions = filtered_releases.map { |x| x.version.to_s }.sort
          expected_versions = ["1.72"]
          expect(filtered_versions).to match_array(expected_versions)
        end
      end

      context "with channel dependency requirement" do
        let(:dependency_requirement) { "beta" }
        let(:dependency_version) { "beta" }

        it "returns no updates for channels" do
          package_details = version_finder.package_details
          filtered_releases = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)

          filtered_versions = filtered_releases.map { |x| x.version.to_s }.sort
          expected_versions = %w()
          expect(filtered_versions).to match_array(expected_versions)
        end
      end
    end

    context "when no matching versions exist" do
      let(:mock_versions) do
        [
          Dependabot::RustToolchain::Version.new("stable"),
          Dependabot::RustToolchain::Version.new("beta")
        ]
      end
      let(:dependency_requirement) { "1.72.0" }
      let(:dependency_version) { "1.72.0" }

      it "returns empty array when no version matches" do
        package_details = version_finder.package_details
        filtered_releases = version_finder.send(:apply_post_fetch_latest_versions_filter, package_details.releases)

        expect(filtered_releases).to be_empty
      end
    end
  end

  def create_release(version_string)
    version = Dependabot::RustToolchain::Version.new(version_string)
    Dependabot::Package::PackageRelease.new(version: version)
  end
end
