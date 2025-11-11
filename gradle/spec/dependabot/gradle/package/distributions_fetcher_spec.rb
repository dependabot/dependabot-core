# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/package/distributions_fetcher"

RSpec.describe Dependabot::Gradle::Package::DistributionsFetcher do
  before do
    stub_request(:get, "https://services.gradle.org/versions/all")
      .to_return(
        status: 200,
        body: fixture("gradle_distributions_metadata", "versions_all.json")
      )
  end

  describe "#available_versions" do
    it {
      expected_versions =
        JSON.parse(fixture("gradle_distributions_metadata", "resolved_versions.json"), { symbolize_names: true })
            .sort_by { |v| v[:version] }

      actual_versions = described_class.available_versions.sort_by { |v| v[:version] }

      expect(actual_versions).to eq(expected_versions)
    }
  end
end
