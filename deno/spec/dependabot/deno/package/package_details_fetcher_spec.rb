# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/package/package_details_fetcher"
require "dependabot/dependency"

RSpec.describe Dependabot::Deno::Package::PackageDetailsFetcher do
  let(:fetcher) { described_class.new(dependency: dependency) }

  context "with a jsr dependency" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "@std/path",
        version: "1.0.0",
        requirements: [{
          requirement: "^1.0.0",
          file: "deno.json",
          groups: ["imports"],
          source: { type: "jsr" }
        }],
        package_manager: "deno"
      )
    end

    before do
      stub_request(:get, "https://jsr.io/@std/path/meta.json")
        .to_return(
          status: 200,
          body: {
            versions: {
              "1.1.4" => { "createdAt" => "2025-12-01T00:00:00Z" },
              "1.0.0" => { "createdAt" => "2024-01-01T00:00:00Z" },
              "0.9.0" => { "yanked" => true, "createdAt" => "2023-06-01T00:00:00Z" }
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns releases with release dates" do
      releases = fetcher.available_versions
      expect(releases.length).to eq(3)

      latest = releases.find { |r| r.version.to_s == "1.1.4" }
      expect(latest.released_at).to eq(Time.parse("2025-12-01T00:00:00Z"))
    end

    it "marks yanked versions with the yanked flag" do
      releases = fetcher.available_versions
      yanked = releases.find { |r| r.version.to_s == "0.9.0" }
      expect(yanked.yanked?).to be true

      not_yanked = releases.find { |r| r.version.to_s == "1.1.4" }
      expect(not_yanked.yanked?).to be false
    end

    it "skips invalid version strings" do
      stub_request(:get, "https://jsr.io/@std/path/meta.json")
        .to_return(
          status: 200,
          body: {
            versions: {
              "1.0.0" => { "createdAt" => "2024-01-01T00:00:00Z" },
              "not-a-version" => { "createdAt" => "2024-01-01T00:00:00Z" }
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      releases = fetcher.available_versions
      expect(releases.map { |r| r.version.to_s }).to eq(["1.0.0"])
    end

    it "returns an empty array on registry failure" do
      stub_request(:get, "https://jsr.io/@std/path/meta.json")
        .to_return(status: 200, body: "not json")

      expect(fetcher.available_versions).to eq([])
    end
  end

  context "with an npm dependency" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "chalk",
        version: "5.3.0",
        requirements: [{
          requirement: "^5.3.0",
          file: "deno.json",
          groups: ["imports"],
          source: { type: "npm" }
        }],
        package_manager: "deno"
      )
    end

    before do
      stub_request(:get, "https://registry.npmjs.org/chalk")
        .to_return(
          status: 200,
          body: {
            "versions" => {
              "5.3.0" => {},
              "5.4.0" => {}
            },
            "time" => {
              "5.3.0" => "2024-01-01T00:00:00Z",
              "5.4.0" => "2025-06-01T00:00:00Z"
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns releases with release dates from the time field" do
      releases = fetcher.available_versions
      expect(releases.length).to eq(2)

      v540 = releases.find { |r| r.version.to_s == "5.4.0" }
      expect(v540.released_at).to eq(Time.parse("2025-06-01T00:00:00Z"))
    end
  end

  context "with an unknown source type" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "something",
        version: "1.0.0",
        requirements: [{
          requirement: "1.0.0",
          file: "deno.json",
          groups: ["imports"],
          source: { type: "unknown" }
        }],
        package_manager: "deno"
      )
    end

    it "returns an empty array" do
      expect(fetcher.available_versions).to eq([])
    end
  end
end
