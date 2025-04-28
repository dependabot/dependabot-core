# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/cargo/package/package_details_fetcher"

RSpec.describe Dependabot::Cargo::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_name) { "es-entity" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "0.3.23",
      requirements: [{
        requirement: "==0.3.23",
        file: "crate.toml",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "cargo"
    )
  end
  let(:dependency_files) { [] }
  let(:credentials) { [] }
  let(:json_url) { "https://crates.io/api/v1/crates/es-entity" }

  let(:latest_release) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Cargo::Version.new("0.3.23"),
      released_at: Time.parse("2025-04-04 07:32:41.023326 UTC"),
      yanked: false,
      yanked_reason: nil,
      downloads: 345,
      url: "https://crates.io/api/v1/crates/es-entity/0.3.23/download",
      package_type: described_class::PACKAGE_TYPE,
      language: Dependabot::Package::PackageLanguage.new(
        name: "rust",
        version: nil,
        requirement: nil
      )
    )
  end

  describe "#fetch" do
    subject(:fetch) { fetcher.fetch }

    context "with a valid response" do
      before do
        stub_request(:get, json_url)
          .to_return(
            status: 200,
            body: fixture("crates_io_responses", "package_fetcher.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches the latest version" do
        result = fetch

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once

        expect(result.releases.size).to be(24)

        first_result = result.releases.first
        expect(first_result.version).to eq(latest_release.version)
        expect(first_result.released_at).to eq(latest_release.released_at)
        expect(first_result.yanked).to eq(latest_release.yanked)
        expect(first_result.yanked_reason).to eq(latest_release.yanked_reason)
        expect(first_result.downloads).to eq(latest_release.downloads)
        expect(first_result.url).to eq(latest_release.url)
        expect(first_result.package_type).to eq(latest_release.package_type)
        expect(first_result.language.name).to eq(latest_release.language.name)
        expect(first_result.language.requirement).to eq(latest_release.language.requirement)
      end
    end
  end
end
