# typed: false
# frozen_string_literal: true

require "cgi"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/elm/package/package_details_fetcher"
require "dependabot/elm/version"
require "dependabot/package/package_release"
require "dependabot/registry_client"
require "excon"
require "json"
require "nokogiri"
require "sorbet-runtime"
require "spec_helper"
require "time"

RSpec.describe Dependabot::Elm::Package::PackageDetailsFetcher do
  describe "#fetch_package_releases" do
    subject(:fetcher) { described_class.new(dependency: dependency) }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        requirements: requirements,
        package_manager: "elm"
      )
    end
    let(:dependency_version) { "2.2.0" }
    let(:dependency_name) { "elm/http" }
    let(:requirements) do
      [{
        file: "elm.json",
        requirement: string_req,
        groups: [],
        source: nil
      }]
    end
    let(:string_req) { "1.0.0 <= v <= 2.2.0" }

    context "when the response is successful" do
      let(:response) { instance_double(Excon::Response, status: 200, body: fixture("elm_jsons", "elm-parser.json")) }

      before do
        allow(Dependabot::RegistryClient).to receive(:get).and_return(response)
      end

      it "returns an array of package releases" do
        releases = fetcher.fetch_package_releases
        expect(releases.size).to eq(2)
        expect(releases[0].version.to_s).to eq("1.0.0")
        expect(releases[0].released_at.to_s).to eq("2018-08-20 13:34:33 +0000")
        expect(releases[1].version.to_s).to eq("1.1.0")
        expect(releases[1].released_at.to_s).to eq("2018-08-30 19:29:06 +0000")
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
