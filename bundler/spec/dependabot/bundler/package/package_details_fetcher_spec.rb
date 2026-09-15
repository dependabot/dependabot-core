# typed: strict
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
        expect(a_request(:get, "https://rubygems.org/info/#{dependency_name}")).not_to have_been_made

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

        it "returns nil" do
          result = fetch

          expect(result).to be_nil
          expect(a_request(:get, json_url)).not_to have_been_made
        end
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
      let(:compact_index_url) { "https://gems.private-registry.example.com/info/my-private-gem" }

      before do
        stub_request(:get, private_versions_url)
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, compact_index_url)
          .to_return(status: 404, body: "Not Found")
      end

      it "returns empty package details" do
        result = fetch

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases).to be_empty
        expect(a_request(:get, private_versions_url)).to have_been_made.once
      end

      context "when the registry supports Compact Index v2" do
        let(:compact_index_response) { fixture("releases_api", "compact_index_v2") }

        before do
          stub_request(:get, compact_index_url)
            .to_return(status: 200, body: compact_index_response)
        end

        it "fetches publication dates and requirements from the compact index" do
          releases = fetch.releases

          expect(releases.map { |release| release.version.to_s }).to eq(%w(1.1.0 1.0.0))
          expect(releases.map(&:released_at)).to eq(
            [Time.iso8601("2025-03-20T14:48:33Z"), Time.iso8601("2025-01-01T12:34:56Z")]
          )
          expect(releases.first.language.requirement)
            .to eq(Dependabot::Bundler::Requirement.new(">= 3.1.0, < 4.0"))
          expect(releases.first.url)
            .to eq("https://gems.private-registry.example.com/gems/my-private-gem-1.1.0.gem")
          expect(a_request(:get, compact_index_url)).to have_been_made.once
        end

        context "with platform-specific versions" do
          let(:compact_index_response) do
            "---\n1.1.0-x86_64-linux |checksum:abc,created_at:2025-03-20T14:48:33Z\n"
          end

          it "separates the version from the platform" do
            release = fetch.releases.first

            expect(release.version.to_s).to eq("1.1.0")
            expect(release.released_at).to eq(Time.iso8601("2025-03-20T14:48:33Z"))
            expect(release.url)
              .to eq("https://gems.private-registry.example.com/gems/my-private-gem-1.1.0-x86_64-linux.gem")
          end
        end

        context "with a replaces_base registry" do
          let(:source) { nil }
          let(:credentials) do
            [
              Dependabot::Credential.new(
                "type" => "rubygems_server",
                "host" => "gems.private-registry.example.com",
                "replaces-base" => true
              )
            ]
          end

          it "uses the replacement registry for compact index metadata" do
            expect(fetch.releases).not_to be_empty
            expect(a_request(:get, compact_index_url)).to have_been_made.once
            expect(a_request(:get, json_url)).not_to have_been_made
          end
        end

        context "with missing or invalid publication dates" do
          let(:compact_index_response) do
            <<~INDEX
              ---
              1.0.0 |checksum:abc
              1.1.0 |checksum:def,created_at:invalid
              1.2.0 |checksum:ghi,created_at:2025-03-20T14:48:33Z
            INDEX
          end

          it "retains undated releases without losing valid publication dates" do
            releases = fetch.releases

            expect(releases.map { |release| release.version.to_s }).to eq(%w(1.2.0 1.1.0 1.0.0))
            expect(releases.map(&:released_at)).to eq([Time.iso8601("2025-03-20T14:48:33Z"), nil, nil])
          end
        end

        context "with an empty response" do
          let(:compact_index_response) { "" }

          it "returns empty package details" do
            expect(fetch.releases).to be_empty
          end
        end

        context "with a malformed response" do
          let(:compact_index_response) { "<html>Not Found</html>" }

          it "returns empty package details" do
            expect(fetch.releases).to be_empty
          end
        end

        context "with malformed lines" do
          let(:compact_index_response) do
            "---\ninvalid\ninvalid |checksum:abc\n1.0.0 |checksum:def,created_at:2025-01-01T12:34:56Z\n"
          end

          it "retains valid releases" do
            expect(fetch.releases.map { |release| release.version.to_s }).to eq(["1.0.0"])
          end
        end
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
