# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/devbox/package/package_details_fetcher"

RSpec.describe Dependabot::Devbox::Package::PackageDetailsFetcher do
  subject(:fetcher) { described_class.new(dependency: dependency) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "python",
      version: "3.10.13",
      requirements: [{
        requirement: "3.10",
        file: "devbox.json",
        groups: [],
        source: { type: "nixhub" }
      }],
      package_manager: "devbox"
    )
  end
  let(:search_url) { "https://search.devbox.sh/v1/search?q=python" }

  describe "#available_versions" do
    context "with a successful response" do
      before do
        stub_request(:get, search_url).to_return(
          status: 200,
          body: {
            packages: [
              # Fuzzy match for a different package — must be ignored.
              { name: "python3", versions: [{ version: "9.9.9", last_updated: 100 }] },
              {
                name: "python",
                versions: [
                  {
                    version: "3.11.2",
                    last_updated: 1_700_000_100,
                    systems: {
                      "aarch64-darwin" => { last_updated: 1_700_000_050 },
                      "x86_64-linux" => { last_updated: 1_700_000_000 }
                    }
                  },
                  { version: "3.10.13", last_updated: 1_600_000_000 },
                  { version: "not-a-version", last_updated: 1_500_000_000 }
                ]
              }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "returns a release per valid version of the exact-name package" do
        expect(fetcher.available_versions.map { |r| r.version.to_s })
          .to contain_exactly("3.11.2", "3.10.13")
      end

      it "uses the earliest per-system last_updated as released_at" do
        release = fetcher.available_versions.find { |r| r.version.to_s == "3.11.2" }
        expect(release.released_at).to eq(Time.at(1_700_000_000).utc)
      end

      it "falls back to the top-level last_updated when no systems are present" do
        release = fetcher.available_versions.find { |r| r.version.to_s == "3.10.13" }
        expect(release.released_at).to eq(Time.at(1_600_000_000).utc)
      end
    end

    context "when the package is not in the results" do
      before do
        stub_request(:get, search_url).to_return(
          status: 200,
          body: { packages: [] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "returns an empty array" do
        expect(fetcher.available_versions).to eq([])
      end
    end

    context "when the registry request times out" do
      before { stub_request(:get, search_url).to_timeout }

      it "returns an empty array" do
        expect(fetcher.available_versions).to eq([])
      end
    end
  end
end
