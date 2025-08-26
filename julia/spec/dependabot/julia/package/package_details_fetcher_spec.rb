# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/package/package_details_fetcher"
require "dependabot/julia/version"

RSpec.describe Dependabot::Julia::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      credentials: credentials
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Example",
      version: "0.5.3",
      requirements: [
        {
          file: "Project.toml",
          requirement: "0.5.3",
          groups: [],
          source: nil
        }
      ],
      package_manager: "julia",
      metadata: { julia_uuid: "7876af07-990d-54b4-ab0e-23690620f79a" }
    )
  end

  let(:credentials) { [] }

  describe "#fetch_package_releases" do
    let(:registry_client) { instance_double(Dependabot::Julia::RegistryClient) }
    let(:available_versions) { ["0.5.0", "0.5.1", "0.5.2", "0.5.3"] }
    let(:release_date1) { Time.parse("2023-01-01T00:00:00Z") }
    let(:release_date2) { Time.parse("2023-02-01T00:00:00Z") }

    before do
      allow(Dependabot::Julia::RegistryClient).to receive(:new)
        .with(credentials: credentials, custom_registries: [])
        .and_return(registry_client)

      allow(registry_client).to receive(:fetch_available_versions)
        .with("Example", "7876af07-990d-54b4-ab0e-23690620f79a")
        .and_return(available_versions)

      allow(registry_client).to receive(:fetch_version_release_date)
        .with("Example", "0.5.0", "7876af07-990d-54b4-ab0e-23690620f79a")
        .and_return(release_date1)

      allow(registry_client).to receive(:fetch_version_release_date)
        .with("Example", "0.5.1", "7876af07-990d-54b4-ab0e-23690620f79a")
        .and_return(release_date2)

      allow(registry_client).to receive(:fetch_version_release_date)
        .with("Example", "0.5.2", "7876af07-990d-54b4-ab0e-23690620f79a")
        .and_return(nil)

      allow(registry_client).to receive(:fetch_version_release_date)
        .with("Example", "0.5.3", "7876af07-990d-54b4-ab0e-23690620f79a")
        .and_return(release_date2)
    end

    it "returns an array of PackageRelease objects" do
      releases = fetcher.fetch_package_releases

      expect(releases).to be_an(Array)
      expect(releases.length).to eq(4)
      expect(releases.all?(Dependabot::Package::PackageRelease)).to be true
    end

    it "creates releases with correct versions" do
      releases = fetcher.fetch_package_releases
      versions = releases.map { |r| r.version.to_s }.sort

      expect(versions).to eq(["0.5.0", "0.5.1", "0.5.2", "0.5.3"])
    end

    it "includes release dates when available" do
      releases = fetcher.fetch_package_releases

      release_zero_five_zero = releases.find { |r| r.version.to_s == "0.5.0" }
      release_zero_five_one = releases.find { |r| r.version.to_s == "0.5.1" }
      release_zero_five_two = releases.find { |r| r.version.to_s == "0.5.2" }

      expect(release_zero_five_zero.released_at).to eq(release_date1)
      expect(release_zero_five_one.released_at).to eq(release_date2)
      expect(release_zero_five_two.released_at).to be_nil
    end

    it "marks the latest version correctly" do
      releases = fetcher.fetch_package_releases
      latest_release = releases.find { |r| r.version.to_s == "0.5.3" }
      other_releases = releases.reject { |r| r.version.to_s == "0.5.3" }

      expect(latest_release.latest).to be true
      expect(other_releases.all? { |r| !r.latest }).to be true
    end

    it "sets correct language information" do
      releases = fetcher.fetch_package_releases

      releases.each do |release|
        expect(release.language.name).to eq("julia")
        expect(release.yanked).to be false
      end
    end

    context "when registry client returns empty versions" do
      let(:available_versions) { [] }

      it "returns empty array" do
        releases = fetcher.fetch_package_releases
        expect(releases).to eq([])
      end
    end

    context "when an error occurs" do
      before do
        allow(registry_client).to receive(:fetch_available_versions)
          .and_raise(StandardError, "Network error")
      end

      it "logs error and returns empty array" do
        expect(Dependabot.logger).to receive(:error)
          .with(/Error while fetching package releases for Example/)

        releases = fetcher.fetch_package_releases
        expect(releases).to eq([])
      end
    end

    context "when release date fetching fails for some versions" do
      before do
        allow(registry_client).to receive(:fetch_version_release_date)
          .with("Example", "0.5.1", "7876af07-990d-54b4-ab0e-23690620f79a")
          .and_raise(StandardError, "Date fetch error")
      end

      it "creates release without date and logs warning" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/Failed to fetch release info for Example version 0.5.1/)

        releases = fetcher.fetch_package_releases
        release_zero_five_one = releases.find { |r| r.version.to_s == "0.5.1" }

        expect(release_zero_five_one.released_at).to be_nil
        expect(releases.length).to eq(4) # Still creates the release
      end
    end
  end
end
