# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/swift/package/package_details_fetcher"

RSpec.describe Dependabot::Swift::Package::PackageDetailsFetcher do
  let(:dependency) { instance_double(Dependabot::Dependency, name: "SwiftNetCDF") }
  let(:credentials) { [] }
  let(:fetcher) { described_class.new(dependency: dependency, credentials: credentials) }

  describe "#fetch_release_details_from_github" do
    let(:response_body) do
      <<-HTML
        <html>
          <body>
            <div class="release-entry">
              <div class="release-header">
                <a href="/patrick-zippenfenig/SwiftNetCDF/releases/tag/v1.0.0">v1.0.0</a>
              </div>
              <relative-time datetime="2023-01-01T00:00:00Z"></relative-time>
            </div>
            <div class="release-entry">
              <div class="release-header">
                <a href="/patrick-zippenfenig/SwiftNetCDF/releases/tag/v1.1.0">v1.1.0</a>
              </div>
              <relative-time datetime="2023-02-01T00:00:00Z"></relative-time>
            </div>
          </body>
        </html>
      HTML
    end

    before do
      allow(Dependabot::RegistryClient).to receive(:get).and_return(
        instance_double(Excon::Response, body: response_body)
      )
    end

    it "fetches and parses release details from GitHub" do
      releases = fetcher.fetch_release_details_from_github

      expect(releases).not_to be_nil
      expect(releases.css("div.release-entry").size).to eq(2)

      first_release = releases.css("div.release-entry").first
      expect(first_release.at_css("div.release-header a").text.strip).to eq("v1.0.0")
      expect(first_release.at_css("relative-time")["datetime"]).to eq("2023-01-01T00:00:00Z")

      second_release = releases.css("div.release-entry").last
      expect(second_release.at_css("div.release-header a").text.strip).to eq("v1.1.0")
      expect(second_release.at_css("relative-time")["datetime"]).to eq("2023-02-01T00:00:00Z")
    end

    it "logs the fetched release details" do
      expect(Dependabot.logger).to receive(:info).with(/Fetched release details:/)
      fetcher.fetch_release_details_from_github
    end
  end

  describe "#fetch_release_details" do
    let(:html_content) do
      <<-HTML
        <html>
          <body>
            <div class="release-entry">
              <div class="release-header">
                <a href="/releases/tag/v1.0.0">v1.0.0</a>
              </div>
              <relative-time datetime="2023-01-01T00:00:00Z"></relative-time>
            </div>
            <div class="release-entry">
              <div class="release-header">
                <a href="/releases/tag/v1.1.0">v1.1.0</a>
              </div>
              <relative-time datetime="2023-02-01T00:00:00Z"></relative-time>
            </div>
          </body>
        </html>
      HTML
    end

    let(:html_doc) { Nokogiri::HTML(html_content) }
    let(:fetcher) { described_class.new(dependency: nil, credentials: []) }

    it "parses the HTML document and returns a hash of release details" do
      release_details = fetcher.fetch_release_details(html_doc: html_doc)

      expect(release_details).to eq({
        "v1.0.0" => "2023-01-01T00:00:00Z",
        "v1.1.0" => "2023-02-01T00:00:00Z"
      })
    end

    it "logs the parsed release details" do
      expect(Dependabot.logger).to receive(:info).with("Parsed release details: {\"v1.0.0\"=>\"2023-01-01T00:00:00Z\", \"v1.1.0\"=>\"2023-02-01T00:00:00Z\"}")
      fetcher.fetch_release_details(html_doc: html_doc)
    end
  end
end
