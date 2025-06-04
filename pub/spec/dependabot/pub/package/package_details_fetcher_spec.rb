# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/pub"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/pub/helpers"
require "dependabot/requirements_update_strategy"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"
require "spec_helper"

RSpec.describe Dependabot::Pub::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "pub"
    )
  end

  let(:requirements) { [] }
  let(:dependency_name) { "lints" }
  let(:requirements_update_strategy) { nil }
  let(:dependency_version) { "0.1.0" }

  let(:dependency_files) { [] }
  let(:credentials) { [] }
  let(:registry_url) { "https://pub.dev/api/packages/#{dependency_name}" }

  describe "#package_details_metadata" do
    context "with packagedetailsfetcher" do
      before do
        stub_request(:get, registry_url).to_return(
          status: 200,
          body: fixture("pub_dev_responses/simple/lints.json")
        )
      end

      it "fetches package details metadata" do
        package_releases = fetcher.package_details_metadata

        package_release = package_releases.first

        expect(package_releases).to be_an(Array)

        expect(package_release.version).to eq(Gem::Version.new("0.1.0"))
        expect(package_release.released_at).to eq(Time.parse("2021-04-27 10:40:00.45138 UTC"))
      end
    end
  end
end
