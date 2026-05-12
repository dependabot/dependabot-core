# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/sbt/package/package_details_fetcher"

RSpec.describe Dependabot::Sbt::Package::PackageDetailsFetcher do
  let(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:credentials) { [] }
  let(:dependency_files) { [build_sbt] }
  let(:build_sbt) do
    Dependabot::DependencyFile.new(
      name: "build.sbt",
      content: fixture("buildfiles", "basic_build.sbt")
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "sbt"
    )
  end
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "33.0.0-jre" }
  let(:dependency_requirements) do
    [{
      file: "build.sbt",
      requirement: "33.0.0-jre",
      groups: [],
      source: nil,
      metadata: nil
    }]
  end

  let(:maven_central_metadata_url) do
    "https://repo.maven.apache.org/maven2/" \
      "com/google/guava/guava/maven-metadata.xml"
  end
  let(:maven_central_base_url) do
    "https://repo.maven.apache.org/maven2/" \
      "com/google/guava/guava"
  end
  let(:maven_central_releases) do
    fixture("maven_metadata", "guava.xml")
  end

  before do
    stub_request(:get, maven_central_metadata_url)
      .to_return(status: 200, body: maven_central_releases)
    stub_request(:get, maven_central_base_url)
      .to_return(status: 404)
  end

  describe "#fetch" do
    subject(:package_details) { fetcher.fetch }

    it "returns a PackageDetails object" do
      expect(package_details).to be_a(Dependabot::Package::PackageDetails)
    end

    it "includes the correct releases" do
      versions = package_details.releases.map { |r| r.version.to_s }
      expect(versions).to include("33.0.0-jre", "33.4.0-jre")
    end

    it "includes all versions from metadata including android variants" do
      versions = package_details.releases.map { |r| r.version.to_s }
      expect(versions).to include("33.0.0-android")
    end

    it "returns releases sorted by version in descending order" do
      versions = package_details.releases.map(&:version)
      expect(versions).to eq(versions.sort.reverse)
    end
  end

  describe "#releases" do
    subject(:releases) { fetcher.releases }

    it "returns PackageRelease objects" do
      expect(releases.first).to be_a(Dependabot::Package::PackageRelease)
    end

    it "includes source_url in releases" do
      expect(releases.first.url).to eq("https://repo.maven.apache.org/maven2")
    end
  end

  describe "#repositories" do
    subject(:repositories) { fetcher.repositories }

    it "includes Maven Central by default" do
      urls = repositories.map { |r| r["url"] }
      expect(urls).to include("https://repo.maven.apache.org/maven2")
    end

    context "with custom resolvers in build file" do
      let(:build_sbt) do
        Dependabot::DependencyFile.new(
          name: "build.sbt",
          content: fixture("buildfiles", "custom_repos_build.sbt")
        )
      end

      it "includes custom resolver URLs" do
        urls = repositories.map { |r| r["url"] }
        expect(urls).to include("https://oss.sonatype.org/content/repositories/releases")
        expect(urls).to include("https://repo.artima.com/releases")
      end
    end

    context "with credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "maven_repository",
              "url" => "https://private.repo.example.com/maven2"
            }
          )
        ]
      end

      it "includes credential-based repositories" do
        urls = repositories.map { |r| r["url"] }
        expect(urls).to include("https://private.repo.example.com/maven2")
      end
    end
  end

  describe "#released?" do
    subject { fetcher.released?(version) }

    let(:version) { Dependabot::Sbt::Version.new("33.4.0-jre") }

    before do
      stub_request(
        :head,
        "https://repo.maven.apache.org/maven2/" \
        "com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.jar"
      ).to_return(status: 200)
    end

    it { is_expected.to be true }

    context "when the artifact is not found" do
      before do
        stub_request(
          :head,
          "https://repo.maven.apache.org/maven2/" \
          "com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.jar"
        ).to_return(status: 404)
      end

      it { is_expected.to be false }
    end
  end

  describe "cross-versioned artifact resolution" do
    let(:dependency_name) { "org.typelevel:cats-core_2.13" }
    let(:dependency_version) { "2.10.0" }
    let(:dependency_requirements) do
      [{
        file: "build.sbt",
        requirement: "2.10.0",
        groups: [],
        source: nil,
        metadata: { packaging_type: "cross-versioned" }
      }]
    end

    let(:maven_central_metadata_url) do
      "https://repo.maven.apache.org/maven2/" \
        "org/typelevel/cats-core_2.13/maven-metadata.xml"
    end
    let(:maven_central_base_url) do
      "https://repo.maven.apache.org/maven2/" \
        "org/typelevel/cats-core_2.13"
    end
    let(:maven_central_releases) do
      fixture("maven_metadata", "cats_core_2.13.xml")
    end

    it "correctly resolves the artifact path with Scala version suffix" do
      details = fetcher.fetch
      versions = details.releases.map { |r| r.version.to_s }
      expect(versions).to include("2.10.0", "2.11.0", "2.12.0")
    end
  end
end
