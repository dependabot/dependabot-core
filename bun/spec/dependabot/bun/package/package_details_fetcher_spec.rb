# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bun/package/package_details_fetcher"
require "dependabot/bun/version"
require "dependabot/bun/requirement"
require "dependabot/package/package_release"
require "dependabot/package/package_language"

RSpec.describe Dependabot::Bun::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_name) { "react" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "16.6.0",
      requirements: [{
        requirement: "^16.0",
        file: "package.json",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "bun"
    )
  end

  let(:dependency_files) { [] }
  let(:credentials) { [] }
  let(:registry_url) { "https://registry.npmjs.org/#{dependency_name}" }

  describe "#fetch" do
    subject(:details) { fetcher.fetch }

    before do
      stub_request(:get, registry_url).to_return(
        status: 200,
        body: fixture("npm_responses", "react.json")
      )
    end

    context "when version field exists" do
      it "includes the requested version in the list" do
        expect(details.releases.map(&:version)).to include(Dependabot::Bun::Version.new("16.6.0"))
      end
    end

    context "when released_at field exists" do
      it "parses the correct release date" do
        release = details.releases.find { |r| r.version.to_s == "16.6.0" }
        expect(release.released_at).to eq(Time.parse("2018-10-23T23:36:06.553Z"))
      end
    end

    context "when version is deprecated" do
      it "marks it as deprecated and includes a reason" do
        release = details.releases.find { |r| r.version.to_s == "0.7.1" }
        expect(release.details["deprecated"]).to be_a(String)
      end
    end

    context "when version is not deprecated" do
      it "is not marked as yanked and has no reason" do
        release = details.releases.find { |r| r.version.to_s == "16.6.0" }
        expect(release.yanked).to be(false)
        expect(release.yanked_reason).to be_nil
      end
    end

    it "includes the correct version URL" do
      release = details.releases.find { |r| r.version.to_s == "16.6.0" }
      expect(release.url).to include("/react/v/16.6.0")
    end

    context "when version includes a node engine" do
      it "includes the node language with requirement" do
        release = details.releases.find { |r| r.version.to_s == "16.6.0" }
        expect(release.language&.name).to eq("node")
        expect(release.language&.requirement.to_s).to eq(">= 0.10.0")
      end
    end

    context "when package_type field is defined" do
      it "parses the repository type" do
        release = details.releases.find { |r| r.version.to_s == "16.6.0" }
        expect(release.package_type).to eq("git")
      end
    end

    context "when version is the latest" do
      it "sets latest to true" do
        latest_version = details.releases.find(&:latest)
        expect(latest_version.version.to_s).to eq("16.6.0")
      end
    end

    context "when version is not the latest" do
      it "sets latest to false" do
        release = details.releases.find { |r| r.version.to_s == "16.5.0" }
        expect(release.latest).to be(false)
      end
    end
  end
end
