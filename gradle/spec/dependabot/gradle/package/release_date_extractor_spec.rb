# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/package/release_date_extractor"
require "dependabot/gradle/version"

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

    context "with Artifactory style repository" do
      let(:repositories) do
        [{ "url" => "https://artifactory.example.com/maven", "auth_headers" => {} }]
      end
      let(:html_listing) do
        <<~HTML
          <html>
            <body>
              <pre><a href="../">../</a>
              <a href="1.0/">1.0/</a>                 24-Jul-2025 10:31    -
              <a href="1.2/">1.2/</a>                 24-Jul-2025 10:33    -
              <a href="1.3.6/">1.3.6/</a>               05-May-2026 13:55    -
              <a href="maven-metadata.xml">maven-metadata.xml</a>   05-May-2026 13:55  443 bytes
              </pre>
            </body>
          </html>
        HTML
      end
      let(:release_info_metadata_fetcher) { ->(_repo) { Nokogiri::HTML(html_listing) } }

      it "extracts release dates from directory listings without title attributes" do
        result = extract_release_dates

        expect(result["1.0"]).to eq({ release_date: Time.parse("24-Jul-2025 10:31") })
        expect(result["1.2"]).to eq({ release_date: Time.parse("24-Jul-2025 10:33") })
        expect(result["1.3.6"]).to eq({ release_date: Time.parse("05-May-2026 13:55") })
        expect(result).not_to have_key("maven-metadata.xml")
      end
    end

    context "with directory listings that use title without trailing slash" do
      let(:repositories) do
        [{ "url" => "https://repo.example.com/maven", "auth_headers" => {} }]
      end
      let(:html_listing) do
        <<~HTML
          <html>
            <body>
              <a href="1.2.3/" title="1.2.3"></a>       2026-05-05 13:55    -
            </body>
          </html>
        HTML
      end
      let(:release_info_metadata_fetcher) { ->(_repo) { Nokogiri::HTML(html_listing) } }

      it "extracts the version using directory href when title omits the trailing slash" do
        result = extract_release_dates

        expect(result["1.2.3"]).to eq({ release_date: Time.parse("2026-05-05 13:55") })
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
              <a href="1.3.0/" title="1.3.0/"></a>       <!-- no date -->
            </body>
          </html>
        HTML
      end
      let(:dependency_metadata_fetcher) { ->(_repo) { Nokogiri::XML(maven_metadata_xml) } }
      let(:release_info_metadata_fetcher) { ->(_repo) { Nokogiri::HTML(html_listing) } }

      it "combines data from both sources without duplicates" do
        result = extract_release_dates
        expect(result["1.2.0"]).to eq({ release_date: Time.utc(2019, 12, 1, 19, 14, 59) })
        expect(result["1.0.0"][:release_date]).to be_a(Time)
        expect(result["1.3.0"]).to eq({ release_date: nil })
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

    # Regression test for https://github.com/dependabot/dependabot-core/issues/14271.
    context "with Gradle Plugin Portal HTML (no dates) followed by a private mirror (with dates)" do
      let(:repositories) do
        [
          { "url" => "https://plugins.gradle.org/m2", "auth_headers" => {} },
          { "url" => "https://artifactory.example.com/artifactory/maven", "auth_headers" => {} }
        ]
      end
      let(:plugin_portal_html) do
        <<~HTML
          <html><body>
            <pre><a href="2.3.10/">2.3.10/</a></pre>
            <pre><a href="2.3.20/">2.3.20/</a></pre>
            <pre><a href="2.3.21/">2.3.21/</a></pre>
          </body></html>
        HTML
      end
      let(:private_mirror_html) do
        <<~HTML
          <html><body>
            <pre><a href="../">../</a>
            <a href="2.3.10/">2.3.10/</a>   2026-01-10 12:00    -
            <a href="2.3.20/">2.3.20/</a>   2026-03-15 09:30    -
            <a href="2.3.21/">2.3.21/</a>   2026-04-02 16:45    -
            </pre>
          </body></html>
        HTML
      end
      let(:plugin_portal_url) { "https://plugins.gradle.org/m2" }
      let(:release_info_metadata_fetcher) do
        lambda do |repo|
          html = repo.fetch("url") == plugin_portal_url ? plugin_portal_html : private_mirror_html
          Nokogiri::HTML(html)
        end
      end

      it "lets real dates from the private mirror overwrite nil dates from the Plugin Portal" do
        result = extract_release_dates

        expect(result["2.3.10"]).to eq({ release_date: Time.parse("2026-01-10 12:00") })
        expect(result["2.3.20"]).to eq({ release_date: Time.parse("2026-03-15 09:30") })
        expect(result["2.3.21"]).to eq({ release_date: Time.parse("2026-04-02 16:45") })
      end
    end

    # Regression test for https://github.com/dependabot/dependabot-core/issues/14271.
    # Specifically covers the XML guard: an earlier repository's HTML listing
    # records a nil placeholder, and a later repository's maven-metadata.xml
    # supplies the real `lastUpdated` for the same version.
    context "when an earlier HTML listing records nil and a later XML metadata has a real date" do
      let(:repositories) do
        [
          { "url" => "https://plugins.gradle.org/m2", "auth_headers" => {} },
          { "url" => "https://artifactory.example.com/artifactory/maven", "auth_headers" => {} }
        ]
      end
      let(:plugin_portal_url) { "https://plugins.gradle.org/m2" }
      let(:plugin_portal_html) do
        <<~HTML
          <html><body>
            <pre><a href="2.3.21/">2.3.21/</a></pre>
          </body></html>
        HTML
      end
      let(:mirror_xml) do
        <<~XML
          <metadata>
            <versioning>
              <latest>2.3.21</latest>
              <lastUpdated>20260402164500</lastUpdated>
            </versioning>
          </metadata>
        XML
      end
      let(:dependency_metadata_fetcher) do
        lambda do |repo|
          xml = repo.fetch("url") == plugin_portal_url ? "" : mirror_xml
          Nokogiri::XML(xml)
        end
      end
      let(:release_info_metadata_fetcher) do
        lambda do |repo|
          html = repo.fetch("url") == plugin_portal_url ? plugin_portal_html : ""
          Nokogiri::HTML(html)
        end
      end

      it "lets the later XML lastUpdated overwrite the earlier nil placeholder" do
        result = extract_release_dates
        expect(result["2.3.21"]).to eq({ release_date: Time.utc(2026, 4, 2, 16, 45, 0) })
      end
    end
  end
end
