# typed: false
# frozen_string_literal: true

require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/hex/package/package_details_fetcher"
require "dependabot/hex/version"
require "dependabot/package/package_release"
require "dependabot/registry_client"
require "spec_helper"

RSpec.describe Dependabot::Hex::Package::PackageDetailsFetcher do
  describe "#fetch_package_releases" do
    subject(:fetcher) { described_class.new(dependency: dependency) }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        requirements: requirements,
        package_manager: "hex"
      )
    end
    let(:dependency_version) { "2.2.0" }
    let(:dependency_name) { "hex/http" }
    let(:requirements) do
      [{
        file: "hex.json",
        requirement: string_req,
        groups: [],
        source: nil
      }]
    end
    let(:string_req) { "1.0.0 <= v <= 2.2.0" }

    context "when the response is successful" do
      let(:response) do
        instance_double(
          Excon::Response,
          status: 200,
          body:
                fixture("package_fetch_response", "hex-parser.json")
        )
      end

      before do
        allow(Dependabot::RegistryClient).to receive(:get).and_return(response)
      end

      it "returns an array of package releases" do
        releases = fetcher.fetch_package_releases
        expect(releases.size).to eq(160)
        expect(releases[0].version.to_s).to eq("1.8.0-rc.3")
        expect(releases[0].released_at.to_s).to eq("2025-05-07 04:40:42 UTC")
        expect(releases[1].version.to_s).to eq("1.8.0-rc.2")
        expect(releases[1].released_at.to_s).to eq("2025-04-30 03:58:52 UTC")
      end
    end

    context "when the response is not successful" do
      let(:response) { instance_double(Excon::Response, status: 404, body: "[]") }

      before do
        allow(Dependabot::RegistryClient).to receive(:get).and_return(response)
      end

      it "returns an empty array" do
        expect(fetcher.fetch_package_releases).to eq([])
      end
    end
  end
end
