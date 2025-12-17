# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/package/release_date_extractor"

RSpec.describe Dependabot::Gradle::Package::ReleaseDateExtractor do
  let(:extractor) do
    described_class.new(
      dependency_name: dependency_name,
      version_class: version_class
    )
  end
  let(:dependency_name) { "com.example:test-library" }
  let(:version_class) { Dependabot::Gradle::Version }

  describe "#extract" do
    subject(:extract_release_dates) do
      extractor.extract(
        repositories: repositories,
        dependency_metadata_fetcher: dependency_metadata_fetcher,
        release_info_metadata_fetcher: release_info_metadata_fetcher
      )
    end

    let(:repositories) { [] }
    let(:dependency_metadata_fetcher) { ->(_repo) { Nokogiri::XML("") } }
    let(:release_info_metadata_fetcher) { ->(_repo) { Nokogiri::HTML("") } }

    context "with empty repositories" do
      it "returns empty hash" do
        expect(extract_release_dates).to eq({})
      end
    end

    context "with Gradle Plugin Portal style repository" do
      let(:repositories) do
        [{ "url" => "https://plugins.gradle.org/m2", "auth_headers" => {} }]
      end
      let(:maven_metadata_xml) do
        <<~XML
          <metadata>
            <versioning>
              <latest>1.2.0</latest>
              <lastUpdated>20191201191459</lastUpdated>
            </versioning>
          </metadata>
        XML
      end
      let(:dependency_metadata_fetcher) { ->(_repo) { Nokogiri::XML(maven_metadata_xml) } }

      it "extracts release date from lastUpdated timestamp" do
        result = extract_release_dates
        expect(result["1.2.0"]).to eq({ release_date: Time.utc(2019, 12, 1, 19, 14, 59) })
      end
    end

    context "with Maven Central style repository" do
      let(:repositories) do
        [{ "url" => "https://repo.maven.apache.org/maven2", "auth_headers" => {} }]
      end
      let(:html_listing) do
        <<~HTML
          <html>
            <body>
              <a href="1.0.0/" title="1.0.0/"></a>       2019-11-01 10:00    -
              <a href="1.1.0/" title="1.1.0/"></a>       2019-12-01 14:30    -
            </body>
          </html>
        HTML
      end
      let(:release_info_metadata_fetcher) { ->(_repo) { Nokogiri::HTML(html_listing) } }

      it "extracts release dates from HTML directory listing" do
        result = extract_release_dates
        expect(result["1.0.0"][:release_date]).to be_a(Time)
        expect(result["1.1.0"][:release_date]).to be_a(Time)
      end
    end

    context "with both repository styles" do
      let(:repositories) do
        [
          { "url" => "https://plugins.gradle.org/m2", "auth_headers" => {} },
          { "url" => "https://repo.maven.apache.org/maven2", "auth_headers" => {} }
        ]
      end
      let(:maven_metadata_xml) do
        <<~XML
          <metadata>
            <versioning>
              <latest>1.2.0</latest>
              <lastUpdated>20191201191459</lastUpdated>
            </versioning>
          </metadata>
        XML
      end
      let(:html_listing) do
        <<~HTML
          <html>
            <body>
              <a href="1.0.0/" title="1.0.0/"></a>       2019-11-01 10:00    -
              <a href="1.2.0/" title="1.2.0/"></a>       2019-12-01 14:30    -
            </body>
          </html>
        HTML
      end
      let(:dependency_metadata_fetcher) { ->(_repo) { Nokogiri::XML(maven_metadata_xml) } }
      let(:release_info_metadata_fetcher) { ->(_repo) { Nokogiri::HTML(html_listing) } }

      it "combines data from both sources without duplicates" do
        result = extract_release_dates
        # Version 1.2.0 should be found from Gradle Plugin Portal first, not overwritten by Maven
        expect(result["1.2.0"]).to eq({ release_date: Time.utc(2019, 12, 1, 19, 14, 59) })
        expect(result["1.0.0"][:release_date]).to be_a(Time)
      end
    end

    context "when parsing fails" do
      let(:repositories) do
        [{ "url" => "https://example.com", "auth_headers" => {} }]
      end
      let(:dependency_metadata_fetcher) do
        ->(_repo) { raise StandardError, "Network error" }
      end

      it "returns empty hash on failure" do
        expect(extract_release_dates).to eq({})
      end
    end
  end
end
