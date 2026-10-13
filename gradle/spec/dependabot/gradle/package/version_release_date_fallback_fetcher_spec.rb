# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/package/version_release_date_fallback_fetcher"

RSpec.describe Dependabot::Gradle::Package::VersionReleaseDateFallbackFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency_name: "io.github.ben-manes.versions",
      repositories: repositories,
      forbidden_urls: [],
      pom_url_builder: ->(repository_url, version) { "#{repository_url}/#{version}.pom" }
    )
  end

  let(:repositories) { [{ "url" => "https://plugins.gradle.org/m2" }] }
  let(:pom_url) { "https://plugins.gradle.org/m2/0.65.0.pom" }
  let(:last_modified) { "Sat, 11 Oct 2025 10:00:00 GMT" }

  describe "#fetch" do
    [200, 204, 299].each do |status|
      context "when the response status is #{status}" do
        before do
          stub_request(:head, pom_url).to_return(status: status, headers: { "Last-Modified" => last_modified })
        end

        it "uses the Last-Modified date" do
          expect(fetcher.fetch("0.65.0")).to eq(Time.utc(2025, 10, 11, 10))
        end
      end
    end

    [199, 300, 301, 304, 400, 401, 403, 404, 500, 503].each do |status|
      context "when the response status is #{status}" do
        before do
          stub_request(:head, pom_url).to_return(status: status, headers: { "Last-Modified" => last_modified })
        end

        it "ignores the Last-Modified date" do
          expect(fetcher.fetch("0.65.0")).to be_nil
        end
      end
    end

    context "with multiple repositories" do
      let(:repositories) do
        [{ "url" => "https://plugins.gradle.org/m2" }, { "url" => "https://repo.maven.apache.org/maven2" }]
      end
      let(:maven_pom_url) { "https://repo.maven.apache.org/maven2/0.65.0.pom" }

      it "returns no date when a success without a date is followed by a 404 with a date" do
        stub_request(:head, pom_url).to_return(status: 200)
        stub_request(:head, maven_pom_url).to_return(
          status: 404,
          headers: { "Last-Modified" => last_modified }
        )

        expect(fetcher.fetch("0.65.0")).to be_nil
        expect(fetcher.fetch("0.65.0")).to be_nil
        expect(a_request(:head, pom_url)).to have_been_made.once
        expect(a_request(:head, maven_pom_url)).to have_been_made.once
      end

      it "continues to a successful repository after an error with a date" do
        stub_request(:head, pom_url).to_return(status: 404, headers: { "Last-Modified" => last_modified })
        stub_request(:head, maven_pom_url).to_return(
          status: 200,
          headers: { "Last-Modified" => "Mon, 11 May 2026 10:08:43 GMT" }
        )

        expect(fetcher.fetch("0.65.0")).to eq(Time.utc(2026, 5, 11, 10, 8, 43))
      end
    end
  end
end
