# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/composer/package/package_details_fetcher"

RSpec.describe Dependabot::Composer::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: credentials,
      ignored_versions: [],
      security_advisories: []
    )
  end

  let(:dependency_name) { "illuminate/support" }
  let(:dependency_files) { [] }
  let(:files) { project_dependency_files(project_name) }
  let(:credentials) { [] }
  let(:json_url) { "https://repo.packagist.org/p2/#{dependency_name}.json" }
  let(:project_name) { "package_details_fetcher" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "12.14.1",
      requirements: [{
        requirement: "==12.14.1",
        file: "composer.json",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "composer"
    )
  end

  let(:latest_release) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Composer::Version.new("12.14.1"),
      released_at: Time.parse("2025-05-13T15:08:45+00:00"),
      yanked: false,
      url: "https://api.github.com/repos/illuminate/support/zipball/e7789d3fd90493d076318df934a92d687e4bc340",
      package_type: described_class::PACKAGE_TYPE,
      language: Dependabot::Package::PackageLanguage.new(
        name: "php",
        version: nil
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
            body: fixture("packagist_responses", "illuminate-support-response.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns the package details" do
        expect(fetch).to be_a(Dependabot::Package::PackageDetails)
        expect(fetch.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once

        first_result = fetch.releases.first
        expect(first_result.version).to eq(latest_release.version)
        expect(first_result.released_at).to eq(latest_release.released_at)
        expect(first_result.url).to eq(latest_release.url)
        expect(first_result.package_type).to eq(latest_release.package_type)
      end
    end
  end
end
