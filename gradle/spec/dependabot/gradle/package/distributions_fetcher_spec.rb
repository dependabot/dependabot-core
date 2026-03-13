# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/package/distributions_fetcher"

RSpec.describe Dependabot::Gradle::Package::DistributionsFetcher do
  before do
    described_class.instance_variable_set(:@available_versions_cache, {})
    described_class.instance_variable_set(:@distributions_checksums, {})

    stub_request(:get, "https://services.gradle.org/versions/all")
      .to_return(
        status: 200,
        body: fixture("gradle_distributions_metadata", "versions_all.json")
      )
  end

  describe "#available_versions" do
    it "fetches versions from the default URL" do
      expected_versions =
        JSON.parse(fixture("gradle_distributions_metadata", "resolved_versions.json"), { symbolize_names: true })
            .sort_by { |v| v[:version] }

      actual_versions = described_class.available_versions.sort_by { |v| v[:version] }

      expect(actual_versions).to eq(expected_versions)
    end

    context "with a custom base URL" do
      before do
        stub_request(:get, "https://mycompany.example.com/gradle/versions/all")
          .to_return(
            status: 200,
            body: fixture("gradle_distributions_metadata", "versions_all.json")
          )
      end

      it "fetches versions from the custom URL" do
        actual_versions = described_class.available_versions(
          base_url: "https://mycompany.example.com/gradle"
        ).sort_by { |v| v[:version] }

        expected_versions =
          JSON.parse(fixture("gradle_distributions_metadata", "resolved_versions.json"), { symbolize_names: true })
              .sort_by { |v| v[:version] }

        expect(actual_versions).to eq(expected_versions)
      end

      it "passes auth headers to the request" do
        stub = stub_request(:get, "https://mycompany.example.com/gradle/versions/all")
               .with(headers: { "Authorization" => "Basic dXNlcjpwYXNz" })
               .to_return(
                 status: 200,
                 body: fixture("gradle_distributions_metadata", "versions_all.json")
               )

        described_class.available_versions(
          base_url: "https://mycompany.example.com/gradle",
          auth_headers: { "Authorization" => "Basic dXNlcjpwYXNz" }
        )

        expect(stub).to have_been_requested
      end
    end
  end

  describe "#resolve_checksum" do
    it "passes auth headers to the checksum request" do
      checksum_url = "https://mycompany.example.com/gradle/distributions/gradle-9.0.0-bin.zip"
      stub = stub_request(:get, "#{checksum_url}.sha256")
             .with(headers: { "Authorization" => "Basic dXNlcjpwYXNz" })
             .to_return(
               status: 200,
               body: "f759b8dd5204e2e3fa4ca3e73f452f087153cf81bac9561eeb854229cc2c5365"
             )

      result = described_class.resolve_checksum(
        checksum_url,
        auth_headers: { "Authorization" => "Basic dXNlcjpwYXNz" }
      )

      expect(stub).to have_been_requested
      expect(result).to eq([
        "#{checksum_url}.sha256",
        "f759b8dd5204e2e3fa4ca3e73f452f087153cf81bac9561eeb854229cc2c5365"
      ])
    end
  end
end
