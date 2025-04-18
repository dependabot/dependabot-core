# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/maven/package/package_details_fetcher"

RSpec.describe Dependabot::Maven::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "23.3-jre",
      requirements: [{
        requirement: "^23.0",
        file: "pom.xml",
        groups: ["dependencies"],
        source: nil,
        metadata: { packaging_type: "jar" }
      }],
      package_manager: "maven"
    )
  end

  let(:dependency_files) { [pom] }
  let(:credentials) { [] }
  let(:pom_fixture_name) { "basic_pom.xml" }

  let(:pom) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: fixture("poms", pom_fixture_name)
    )
  end

  before do
    stub_request(:get, "https://repo.maven.apache.org/maven2/com/google/guava/guava/maven-metadata.xml")
      .to_return(status: 200, body: fixture("maven_central_metadata", "with_release.xml"))
    stub_request(:get, "https://repo.maven.apache.org/maven2/com/google/guava/guava")
      .to_return(status: 200, body: fixture("maven_central_metadata", "with_release.html"))
    stub_request(:head, "https://repo.maven.apache.org/maven2/com/google/guava/guava/23.6-jre/guava-23.6-jre.jar")
      .to_return(status: 200)
  end

  describe "#fetch" do
    subject(:details) { fetcher.fetch }

    it "returns a PackageDetails object with releases" do
      expect(details).to be_a(Dependabot::Package::PackageDetails)
      expect(details.releases).not_to be_empty
    end

    context "when version is not deprecated" do
      it "does not set released_at to nil for a released version" do
        release = details.releases.find { |r| r.version.to_s == "23.6-jre" }
        expect(release.released_at).not_to be_nil
      end
    end
  end

  describe "#releases" do
    subject(:releases) { fetcher.releases }

    it "returns all the releases" do
      expect(releases.count).to eq(70)
    end

    it "includes the correct version" do
      release = releases.find { |r| r.version.to_s == "23.6-jre" }
      expect(release).not_to be_nil
      expect(release.version.to_s).to eq("23.6-jre")
    end

    it "returns a sorted list of releases" do
      expect(releases.first.version.to_s).to eq("23.7-rc1-jre")
      expect(releases.last.version.to_s).to eq("r03")
    end
  end

  describe "#released?" do
    subject(:released_check) { fetcher.released?(version) }

    let(:version) { Dependabot::Maven::Version.new("23.6-jre") }

    it "returns true for a released version" do
      expect(released_check).to be(true)
    end

    it "returns false for an unreleased version" do
      # Update the URL stub to simulate a 404 (not found) response for an unreleased version
      stub_request(:head, "https://repo.maven.apache.org/maven2/com/google/guava/guava/23.7-jre/guava-23.7-jre.jar")
        .to_return(status: 404)

      unreleased_version = Dependabot::Maven::Version.new("23.7-jre")
      expect(fetcher.released?(unreleased_version)).to be(false)
    end
  end
end
