# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dotnet_sdk/package/package_details_fetcher"

RSpec.describe Dependabot::DotnetSdk::Package::PackageDetailsFetcher do
  subject(:fetcher) { described_class.new(dependency: dependency) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "dotnet-sdk",
      version: "8.0.300",
      requirements: [],
      package_manager: "dotnet_sdk",
      metadata: {
        allow_prerelease: false
      }
    )
  end

  let(:releases_index_url) { Dependabot::DotnetSdk::Package::PackageDetailsFetcher::RELEASES_INDEX_URL }
  let(:releases_index_body) { fixture("releases", "releases-index-small.json") }

  before do
    stub_request(:get, releases_index_url)
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: releases_index_body)

    stub_request(:get, "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: fixture("releases", "releases-8.0.json"))

    stub_request(:get, "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/9.0/releases.json")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: fixture("releases", "releases-9.0.json"))
  end

  describe "#fetch" do
    context "when releases are successfully fetched" do
      it "returns package details with releases" do
        result = fetcher.fetch

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.dependency).to eq(dependency)
        expect(result.releases).not_to be_empty
      end

      it "returns releases in descending order by version" do
        result = fetcher.fetch
        versions = result.releases.map { |x| x.version.to_s }

        # Versions should be in descending order (latest first)
        expect(versions).to eq(versions.sort { |a, b| Gem::Version.new(b) <=> Gem::Version.new(a) })
      end

      it "removes duplicate versions" do
        result = fetcher.fetch
        versions = result.releases.map { |x| x.version.to_s }

        expect(versions).to eq(versions.uniq)
      end

      it "includes release dates" do
        result = fetcher.fetch

        result.releases.each do |release|
          expect(release.released_at).to be_a(Time)
        end
      end

      it "creates versions using DotnetSdk::Version" do
        result = fetcher.fetch

        result.releases.each do |release|
          expect(release.version).to be_a(Dependabot::DotnetSdk::Version)
        end
      end
    end

    context "when releases index request fails" do
      before do
        stub_request(:get, releases_index_url)
          .with(headers: { "Accept" => "application/json" })
          .to_return(status: 500)
      end

      it "returns empty package details" do
        result = fetcher.fetch

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases).to be_empty
      end
    end

    context "when releases index returns invalid JSON" do
      before do
        stub_request(:get, releases_index_url)
          .with(headers: { "Accept" => "application/json" })
          .to_return(status: 200, body: "invalid json")
      end

      it "raises a JSON parser error" do
        expect { fetcher.fetch }.to raise_error(JSON::ParserError)
      end
    end

    context "when individual release channel request fails" do
      before do
        stub_request(:get, "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json")
          .with(headers: { "Accept" => "application/json" })
          .to_return(status: 404, body: "")
      end

      it "raises an error due to invalid JSON" do
        expect { fetcher.fetch }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          /Invalid JSON response from/
        )
      end
    end

    context "when individual release channel returns invalid JSON" do
      before do
        stub_request(:get, "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json")
          .with(headers: { "Accept" => "application/json" })
          .to_return(status: 200, body: "invalid json")
      end

      it "raises DependencyFileNotResolvable error" do
        expect { fetcher.fetch }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          /Invalid JSON response from/
        )
      end
    end

    context "with empty releases index" do
      let(:releases_index_body) { fixture("releases", "releases-index-empty.json") }

      it "returns empty package details" do
        result = fetcher.fetch

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases).to be_empty
      end
    end

    context "with releases that have legacy SDK format" do
      let(:legacy_release_json) do
        {
          "releases" => [
            {
              "release-date" => "2023-01-01",
              "sdk" => {
                "version" => "7.0.100"
              }
            }
          ]
        }.to_json
      end

      before do
        stub_request(:get, "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json")
          .with(headers: { "Accept" => "application/json" })
          .to_return(status: 200, body: legacy_release_json)
      end

      it "extracts SDK version from legacy format" do
        result = fetcher.fetch

        expect(result.releases.map { |x| x.version.to_s }).to include("7.0.100")
      end
    end

    context "with releases that have modern SDKs array format" do
      let(:modern_release_json) do
        {
          "releases" => [
            {
              "release-date" => "2023-01-01",
              "sdks" => [
                { "version" => "7.0.101" },
                { "version" => "7.0.102" }
              ]
            }
          ]
        }.to_json
      end

      before do
        stub_request(:get, "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json")
          .with(headers: { "Accept" => "application/json" })
          .to_return(status: 200, body: modern_release_json)
      end

      it "extracts all SDK versions from modern format" do
        result = fetcher.fetch

        versions = result.releases.map { |x| x.version.to_s }
        expect(versions).to include("7.0.101", "7.0.102")
      end
    end

    context "with releases missing required fields" do
      let(:incomplete_release_json) do
        {
          "releases" => [
            {
              # Missing release-date
              "sdk" => {
                "version" => "7.0.100"
              }
            },
            {
              "release-date" => "2023-01-01"
              # Missing SDK version
            },
            {
              "release-date" => "2023-01-02",
              "sdks" => [
                { "version" => "7.0.103" },
                {} # SDK without version
              ]
            }
          ]
        }.to_json
      end

      before do
        stub_request(:get, "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json")
          .with(headers: { "Accept" => "application/json" })
          .to_return(status: 200, body: incomplete_release_json)
      end

      it "skips incomplete releases and extracts valid ones" do
        result = fetcher.fetch

        versions = result.releases.map { |x| x.version.to_s }
        expect(versions).to include("7.0.103")
        expect(versions).not_to include("7.0.100") # Missing release-date
      end
    end

    context "when memoization is tested" do
      it "returns the same instance when called multiple times" do
        first_result = fetcher.fetch
        second_result = fetcher.fetch

        expect(first_result).to be(second_result)
      end
    end
  end
end
