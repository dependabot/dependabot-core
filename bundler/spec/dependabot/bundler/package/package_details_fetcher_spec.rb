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

      context "when dependency uses a git source" do
        let(:source) do
          {
            type: "git",
            url: "git@github.com/dependabot/dependabot-common"
          }
        end

        it "returns an empty result" do
          result = fetch

          expect(result).to be_a(Dependabot::Package::PackageDetails)
          expect(result.releases).to be_empty
          expect(a_request(:get, json_url)).not_to have_been_made
        end
      end
    end

    describe "GitHub Package Registry support" do
      let(:dependency_name) { "json" }
      let(:source) do
        {
          type: "rubygems",
          url: "https://rubygems.pkg.github.com/dsp-testing/"
        }
      end
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "rubygems_server",
              "host" => "rubygems.pkg.github.com",
              "token" => "ghp_test_token_123"
            }
          )
        ]
      end
      let(:github_api_url) { "https://api.github.com/orgs/dsp-testing/packages/rubygems/json/versions" }

      context "when package exists in GitHub registry" do
        let(:github_api_response) do
          [
            {
              "id" => 123,
              "name" => "2.12.2",
              "created_at" => "2023-09-01T10:00:00Z",
              "updated_at" => "2023-09-01T10:00:00Z"
            },
            {
              "id" => 122,
              "name" => "2.12.1",
              "created_at" => "2023-08-15T09:30:00Z",
              "updated_at" => "2023-08-15T09:30:00Z"
            },
            {
              "id" => 121,
              "name" => "2.11.0",
              "created_at" => "2023-07-01T08:00:00Z",
              "updated_at" => "2023-07-01T08:00:00Z"
            }
          ]
        end

        before do
          stub_request(:get, github_api_url)
            .with(
              headers: {
                "Accept" => "application/vnd.github.v3+json",
                "Authorization" => "Bearer ghp_test_token_123"
              }
            )
            .to_return(
              status: 200,
              body: github_api_response.to_json,
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "returns package details with all versions" do
          result = fetch

          expect(result).to be_a(Dependabot::Package::PackageDetails)
          expect(result.releases.length).to eq(3)

          # Check versions are in correct order (oldest first)
          versions = result.releases.map { |release| release.version.to_s }
          expect(versions).to eq(["2.12.2", "2.12.1", "2.11.0"])
        end

        it "creates package releases with correct GitHub attributes" do
          result = fetch
          latest_release = result.releases.first

          expect(latest_release.version.to_s).to eq("2.12.2")
          expect(latest_release.released_at).to eq(Time.parse("2023-09-01T10:00:00Z"))
          expect(latest_release.downloads).to eq(0) # GitHub doesn't provide download counts
          expect(latest_release.url).to eq("https://rubygems.pkg.github.com/dsp-testing/gems/json-2.12.2.gem")
          expect(latest_release.yanked).to be false
          expect(latest_release.package_type).to eq("gem")
          expect(latest_release.language.name).to eq("ruby")
          expect(latest_release.language.requirement).to be_nil # GitHub doesn't provide ruby version
        end

        it "makes authenticated request to GitHub API" do
          fetch

          expect(
            a_request(:get, github_api_url)
                        .with(
                          headers: {
                            "Accept" => "application/vnd.github.v3+json",
                            "Authorization" => "Bearer ghp_test_token_123"
                          }
                        )
          ).to have_been_made.once
        end
      end

      context "when package is not found in GitHub registry" do
        before do
          stub_request(:get, github_api_url)
            .with(
              headers: {
                "Accept" => "application/vnd.github.v3+json",
                "Authorization" => "Bearer ghp_test_token_123"
              }
            )
            .to_return(status: 404, body: "Not Found")
        end

        it "returns empty package details" do
          result = fetch

          expect(result).to be_a(Dependabot::Package::PackageDetails)
          expect(result.releases).to be_empty
        end

        it "logs package not found error" do
          expect(Dependabot.logger).to receive(:info)
            .with("Failed to fetch versions for 'json' from GitHub Packages. " \
                  "Status: 404 (Package not found in GitHub Registry)")

          fetch
        end
      end

      context "when GitHub API returns server error" do
        before do
          stub_request(:get, github_api_url)
            .to_return(status: 500, body: "Internal Server Error")
        end

        it "returns empty package details" do
          result = fetch

          expect(result).to be_a(Dependabot::Package::PackageDetails)
          expect(result.releases).to be_empty
        end

        it "logs server error" do
          expect(Dependabot.logger).to receive(:info)
            .with("Failed to fetch versions for 'json' from GitHub Packages. Status: 500")

          fetch
        end
      end

      context "when GitHub API returns invalid JSON" do
        before do
          stub_request(:get, github_api_url)
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

        it "logs JSON parsing error" do
          expect(Dependabot.logger).to receive(:info)
            .with(/Failed to parse GitHub Packages response:/)

          fetch
        end
      end

      context "when no GitHub token is provided" do
        let(:credentials) { [] }

        before do
          stub_request(:get, github_api_url)
            .with(
              headers: {
                "Accept" => "application/vnd.github.v3+json",
                "Authorization" => "Bearer "
              }
            )
            .to_return(status: 401, body: "Unauthorized")
        end

        it "makes request with empty authorization header" do
          fetch

          expect(
            a_request(:get, github_api_url)
                        .with(
                          headers: {
                            "Accept" => "application/vnd.github.v3+json",
                            "Authorization" => "Bearer "
                          }
                        )
          ).to have_been_made.once
        end
      end
    end

    describe "#github_token" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "rubygems_server",
              "host" => "rubygems.pkg.github.com",
              "token" => "ghp_test_token_123"
            }
          )
        ]
      end

      it "extracts token from rubygems_server credentials" do
        expect(fetcher.send(:github_token)).to eq("ghp_test_token_123")
      end

      context "when no matching credentials" do
        let(:credentials) { [] }

        it "returns nil" do
          expect(fetcher.send(:github_token)).to be_nil
        end
      end

      context "with multiple credential types" do
        let(:credentials) do
          [
            Dependabot::Credential.new(
              {
                "type" => "git_source",
                "host" => "github.com",
                "token" => "different_token"
              }
            ),
            Dependabot::Credential.new(
              {
                "type" => "rubygems_server",
                "host" => "rubygems.pkg.github.com",
                "token" => "correct_token"
              }
            )
          ]
        end

        it "returns the correct GitHub Package Registry token" do
          expect(fetcher.send(:github_token)).to eq("correct_token")
        end
      end
    end

    describe "#get_url_from_dependency" do
      context "with GitHub Package Registry source URL" do
        let(:source) do
          {
            type: "rubygems",
            url: "https://rubygems.pkg.github.com/dsp-testing/"
          }
        end

        it "returns URL without trailing slash" do
          expect(fetcher.send(:get_url_from_dependency, dependency))
            .to eq("https://rubygems.pkg.github.com/dsp-testing")
        end
      end

      context "without source URL" do
        let(:source) { { type: "rubygems" } }

        it "returns nil" do
          expect(fetcher.send(:get_url_from_dependency, dependency)).to be_nil
        end
      end
    end
  end
end
