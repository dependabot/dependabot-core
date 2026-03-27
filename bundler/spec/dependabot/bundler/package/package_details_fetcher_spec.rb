# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/bundler/package/package_details_fetcher"

RSpec.describe Dependabot::Bundler::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_name) { "dependabot-common" }
  let(:source) { nil }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "0.302.0",
      requirements: [{
        requirement: "==0.302.0",
        file: "Gemfile",
        groups: ["dependencies"],
        source: source
      }],
      package_manager: "bundler"
    )
  end
  let(:dependency_files) { [] }
  let(:credentials) { [] }
  let(:json_url) { "https://rubygems.org/api/v1/versions/#{dependency_name}.json" }

  let(:latest_release) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Bundler::Version.new("0.302.0"),
      released_at: Time.parse("2025-03-20 14:48:33.295Z"),
      yanked: false,
      yanked_reason: nil,
      downloads: 382,
      url: "https://rubygems.org/gems/dependabot-common-0.302.0.gem",
      package_type: described_class::PACKAGE_TYPE,
      language: Dependabot::Package::PackageLanguage.new(
        name: "ruby",
        version: nil,
        requirement: Dependabot::Bundler::Requirement.new([">= 3.1.0"])
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
            body: fixture("releases_api", "dependabot_common.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches the latest version" do
        result = fetch

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once

        expect(result.releases.size).to be(882)

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

    context "with error responses" do
      context "when response has empty body" do
        before do
          stub_request(:get, json_url)
            .to_return(
              status: 200,
              body: "",
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "return empty package details" do
          result = fetch

          expect(result).to be_a(Dependabot::Package::PackageDetails)
          expect(result.releases).to be_empty
        end

        it "logs the error" do
          expect(Dependabot.logger).to receive(:info)
            .with("Empty response body for '#{dependency_name}' from 'https://rubygems.org'")

          fetch
        end
      end

      context "when response body is not an array" do
        before do
          stub_request(:get, json_url)
            .to_return(
              status: 200,
              body: '{"error": "Something went wrong"}',
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "returns empty package details" do
          result = fetch

          expect(result).to be_a(Dependabot::Package::PackageDetails)
          expect(result.releases).to be_empty
        end

        it "logs the error" do
          expect(Dependabot.logger).to receive(:info)
            .with("Unexpected response format for '#{dependency.name}' from 'https://rubygems.org'")

          fetch
        end
      end

      context "when invalid JSON is returned" do
        before do
          stub_request(:get, json_url)
            .to_return(
              status: 200,
              body: "invalid json{",
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "returns empty package details" do
          result = fetch

          expect(result).to be_a(Dependabot::Package::PackageDetails)
          expect(result.releases).to be_empty
        end

        it "logs the error" do
          expect(Dependabot.logger).to receive(:info)
            .with("Failed to parse JSON response for '#{dependency.name}' from 'https://rubygems.org'")

          fetch
        end
      end
    end

    context "when registry does not support versions API" do
      let(:dependency_name) { "my-private-gem" }
      let(:source) do
        {
          type: "rubygems",
          url: "https://gems.private-registry.example.com/"
        }
      end
      let(:private_versions_url) do
        "https://gems.private-registry.example.com/api/v1/versions/my-private-gem.json"
      end

      before do
        stub_request(:get, private_versions_url)
          .to_return(status: 404, body: "Not Found")
      end

      it "returns empty package details" do
        result = fetch

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases).to be_empty
        expect(a_request(:get, private_versions_url)).to have_been_made.once
      end
    end

    describe "#get_url_from_dependency" do
      context "with a source URL with trailing slash" do
        let(:source) do
          {
            type: "rubygems",
            url: "https://gems.private-registry.example.com/"
          }
        end

        it "returns URL without trailing slash" do
          expect(fetcher.send(:get_url_from_dependency, dependency))
            .to eq("https://gems.private-registry.example.com")
        end
      end

      context "without source URL" do
        let(:source) { { type: "rubygems" } }

        it "returns nil" do
          expect(fetcher.send(:get_url_from_dependency, dependency)).to be_nil
        end
      end
    end

    describe "replaces_base credential support" do
      let(:private_registry_url) { "https://gems.example.com/api/v1/versions/#{dependency_name}.json" }

      context "when a replaces_base rubygems_server credential exists" do
        let(:credentials) do
          [
            Dependabot::Credential.new(
              {
                "type" => "rubygems_server",
                "host" => "gems.example.com",
                "token" => "secret",
                "replaces-base" => true
              }
            )
          ]
        end

        context "when dependency has no source in requirements" do
          let(:source) { nil }

          before do
            stub_request(:get, private_registry_url)
              .to_return(
                status: 200,
                body: fixture("releases_api", "dependabot_common.json"),
                headers: { "Content-Type" => "application/json" }
              )
          end

          it "queries the private registry instead of rubygems.org" do
            result = fetch

            expect(result).to be_a(Dependabot::Package::PackageDetails)
            expect(result.releases).not_to be_empty
            expect(a_request(:get, private_registry_url)).to have_been_made.once
            expect(a_request(:get, json_url)).not_to have_been_made
          end
        end

        context "when dependency has explicit source in requirements" do
          let(:source) do
            {
              type: "rubygems",
              url: "https://other-registry.example.com"
            }
          end

          let(:explicit_url) { "https://other-registry.example.com/api/v1/versions/#{dependency_name}.json" }

          before do
            stub_request(:get, explicit_url)
              .to_return(
                status: 200,
                body: fixture("releases_api", "dependabot_common.json"),
                headers: { "Content-Type" => "application/json" }
              )
          end

          it "uses the explicit source URL over the replaces_base credential" do
            result = fetch

            expect(result).to be_a(Dependabot::Package::PackageDetails)
            expect(a_request(:get, explicit_url)).to have_been_made.once
            expect(a_request(:get, private_registry_url)).not_to have_been_made
          end
        end
      end

      context "when no replaces_base credential exists" do
        let(:credentials) { [] }
        let(:source) { nil }

        before do
          stub_request(:get, json_url)
            .to_return(
              status: 200,
              body: fixture("releases_api", "dependabot_common.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "falls back to rubygems.org" do
          result = fetch

          expect(result).to be_a(Dependabot::Package::PackageDetails)
          expect(a_request(:get, json_url)).to have_been_made.once
        end
      end

      context "when a non-replaces_base rubygems_server credential exists" do
        let(:credentials) do
          [
            Dependabot::Credential.new(
              {
                "type" => "rubygems_server",
                "host" => "gems.example.com",
                "token" => "secret"
              }
            )
          ]
        end
        let(:source) { nil }

        before do
          stub_request(:get, json_url)
            .to_return(
              status: 200,
              body: fixture("releases_api", "dependabot_common.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "falls back to rubygems.org" do
          result = fetch

          expect(result).to be_a(Dependabot::Package::PackageDetails)
          expect(a_request(:get, json_url)).to have_been_made.once
          expect(a_request(:get, private_registry_url)).not_to have_been_made
        end
      end
    end
  end
end
