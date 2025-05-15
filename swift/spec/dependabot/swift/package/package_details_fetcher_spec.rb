# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/swift/package/package_details_fetcher"

RSpec.describe Dependabot::Swift::Package::PackageDetailsFetcher do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "patrick-zippenfenig/SwiftNetCDF",
      version: "v1.1.7",
      requirements: [],
      package_manager: "swift"
    )
  end

  let(:credentials) { [] }
  let(:fetcher) { described_class.new(dependency: dependency, credentials: credentials) }

  describe "#fetch_version_and_release_date" do
    context "when the API returns a successful response" do
      let(:json_response) do
        <<~JSON
          [
            {
              "tag_name": "v1.1.7",
              "published_at": "2023-10-01T00:00:00Z"
            },
            {
              "tag_name": "v1.1.6",
              "published_at": "2023-11-01T00:00:00Z"
            }
          ]
        JSON
      end

      before do
        response_double = instance_double(Excon::Response, status: 200, body: json_response)
        allow(Excon).to receive(:get).and_return(response_double)
      end

      it "fetches and parses the version and release date" do
        result = fetcher.fetch_version_and_release_date

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases.size).to eq(2)
        expect(result.releases.first.version.to_s).to eq("1.1.7")
        expect(result.releases.first.released_at).to eq(Time.parse("2023-10-01T00:00:00Z"))
      end
    end

    context "when the API returns an empty response" do
      before do
        response_double = instance_double(Excon::Response, status: 200, body: "[]")
        allow(Excon).to receive(:get).and_return(response_double)
      end

      it "returns an empty PackageDetails object" do
        result = fetcher.fetch_version_and_release_date

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases).to be_empty
      end
    end

    context "when the API returns an error response" do
      before do
        response_double = instance_double(Excon::Response, status: 404, body: "")
        allow(Excon).to receive(:get).and_return(response_double)
      end

      it "raises an error" do
        expect { fetcher.fetch_version_and_release_date }.to raise_error("Failed to fetch releases: 404")
      end
    end
  end

  describe "#package_details" do
    let(:releases) do
      [
        fetcher.package_release(
          version: "v1.1.7",
          released_at: Time.parse("2023-10-01T00:00:00Z"),
          url: "https://api.github.com/repos/patrick-zippenfenig/SwiftNetCDF/releases"
        ),
        fetcher.package_release(
          version: "v1.1.6",
          released_at: Time.parse("2023-11-01T00:00:00Z"),
          url: "https://api.github.com/repos/patrick-zippenfenig/SwiftNetCDF/releases"
        )
      ]
    end

    it "creates a PackageDetails object with unique releases" do
      result = fetcher.package_details(releases)

      expect(result).to be_a(Dependabot::Package::PackageDetails)
      expect(result.releases.size).to eq(2)
      expect(result.releases.map { |x| x.version.to_s }).to eq(["1.1.7", "1.1.6"])
    end
  end

  describe "#package_release" do
    it "creates a PackageRelease object with the correct attributes" do
      release = fetcher.package_release(
        version: "v1.1.7",
        released_at: Time.parse("2023-10-01T00:00:00Z"),
        url: "https://api.github.com/repos/patrick-zippenfenig/SwiftNetCDF/releases"
      )

      expect(release).to be_a(Dependabot::Package::PackageRelease)
      expect(release.version.to_s).to eq("1.1.7")
      expect(release.released_at).to eq(Time.parse("2023-10-01T00:00:00Z"))
      expect(release.url).to eq("https://api.github.com/repos/patrick-zippenfenig/SwiftNetCDF/releases")
      expect(release.package_type).to eq("swift")
    end
  end
end
