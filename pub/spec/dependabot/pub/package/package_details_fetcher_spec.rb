# typed: strict
# frozen_string_literal: true

require "json"
require "time"
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

      context "with a path-prefixed registry URL ending in a slash" do
        let(:registry_url) { "https://registry.example.com/repository/pub/api/packages/#{dependency_name}" }
        let(:requirements) do
          [{
            file: "pubspec.yaml",
            requirement: "any",
            groups: [],
            source: {
              "description" => {
                "name" => dependency_name,
                "url" => "https://registry.example.com/repository/pub/"
              },
              "type" => "hosted"
            }
          }]
        end

        it "fetches package details using a single path separator" do
          expect(fetcher.package_details_metadata).not_to be_empty
          expect(WebMock).to have_requested(:get, registry_url).once
        end
      end
    end

    context "when the registry returns a server error" do
      before do
        stub_request(:get, registry_url).to_return(status: 503, body: "")
      end

      it "returns an empty list rather than partial metadata" do
        expect(fetcher.package_details_metadata).to eq([])
      end
    end

    context "when the response body is not valid JSON" do
      before do
        stub_request(:get, registry_url).to_return(status: 200, body: "not json")
      end

      it "returns an empty list rather than partial metadata" do
        expect(fetcher.package_details_metadata).to eq([])
      end
    end

    context "when a later release has an unparseable publish date" do
      before do
        body = {
          "name" => dependency_name,
          "versions" => [
            { "version" => "1.0.0", "published" => "2021-04-27T10:40:00.000Z" },
            { "version" => "1.1.0", "published" => "not-a-date" }
          ]
        }.to_json
        stub_request(:get, registry_url).to_return(status: 200, body: body)
      end

      it "discards the partial result instead of returning the releases parsed so far" do
        expect(fetcher.package_details_metadata).to eq([])
      end
    end
  end
end
