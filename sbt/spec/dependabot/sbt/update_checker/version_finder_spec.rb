# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/sbt/update_checker/version_finder"

RSpec.describe Dependabot::Sbt::UpdateChecker::VersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      cooldown_options: cooldown_options
    )
  end
  let(:version_class) { Dependabot::Sbt::Version }
  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:cooldown_options) { nil }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "sbt"
    )
  end
  let(:dependency_files) { [build_sbt] }
  let(:build_sbt) do
    Dependabot::DependencyFile.new(
      name: "build.sbt",
      content: fixture("buildfiles", "basic_build.sbt")
    )
  end

  let(:dependency_requirements) do
    [{
      file: "build.sbt",
      requirement: dependency_version,
      groups: [],
      source: nil,
      metadata: nil
    }]
  end
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "33.0.0-jre" }

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
  let(:maven_central_version_files_url) do
    "https://repo.maven.apache.org/maven2/" \
      "com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.jar"
  end

  before do
    stub_request(:get, maven_central_metadata_url)
      .to_return(status: 200, body: maven_central_releases)
    stub_request(:get, maven_central_base_url)
      .to_return(status: 404)
    stub_request(:head, maven_central_version_files_url)
      .to_return(status: 200)
  end

  describe "class hierarchy" do
    it "inherits from SharedVersionFinder" do
      expect(described_class < Dependabot::Maven::Shared::SharedVersionFinder).to be true
    end
  end

  describe "#latest_version_details" do
    subject(:latest_version_details) { finder.latest_version_details }

    its([:version]) { is_expected.to eq(version_class.new("33.4.0-jre")) }

    its([:source_url]) do
      is_expected.to eq("https://repo.maven.apache.org/maven2")
    end

    context "when the latest version hasn't actually been released" do
      before do
        stub_request(:head, maven_central_version_files_url)
          .to_return(status: 404)
        stub_request(
          :head,
          "https://repo.maven.apache.org/maven2/" \
          "com/google/guava/guava/33.3.0-jre/guava-33.3.0-jre.jar"
        ).to_return(status: 200)
      end

      its([:version]) { is_expected.to eq(version_class.new("33.3.0-jre")) }
    end

    context "with a cross-versioned Scala dependency" do
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
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/typelevel/cats-core_2.13/2.12.0/cats-core_2.13-2.12.0.jar"
      end

      its([:version]) { is_expected.to eq(version_class.new("2.12.0")) }

      it "excludes pre-release versions" do
        # 2.13.0-RC1 should not be returned
        expect(latest_version_details[:version]).not_to eq(version_class.new("2.13.0-RC1"))
      end
    end

    context "when the user wants a pre-release" do
      let(:dependency_name) { "com.typesafe.akka:akka-actor_2.13" }
      let(:dependency_version) { "2.9.0-M1" }
      let(:dependency_requirements) do
        [{
          file: "build.sbt",
          requirement: "2.9.0-M1",
          groups: [],
          source: nil,
          metadata: { packaging_type: "cross-versioned" }
        }]
      end

      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/" \
          "com/typesafe/akka/akka-actor_2.13/maven-metadata.xml"
      end
      let(:maven_central_base_url) do
        "https://repo.maven.apache.org/maven2/" \
          "com/typesafe/akka/akka-actor_2.13"
      end
      let(:maven_central_releases) do
        fixture("maven_metadata", "akka_actor_2.13.xml")
      end
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "com/typesafe/akka/akka-actor_2.13/2.9.3/akka-actor_2.13-2.9.3.jar"
      end

      its([:version]) { is_expected.to eq(version_class.new("2.9.3")) }
    end

    context "with ignored versions" do
      let(:ignored_versions) { [">= 33.3.0"] }

      before do
        stub_request(
          :head,
          "https://repo.maven.apache.org/maven2/" \
          "com/google/guava/guava/33.2.0-jre/guava-33.2.0-jre.jar"
        ).to_return(status: 200)
      end

      its([:version]) { is_expected.to eq(version_class.new("33.2.0-jre")) }
    end

    context "with custom repositories" do
      let(:build_sbt) do
        Dependabot::DependencyFile.new(
          name: "build.sbt",
          content: fixture("buildfiles", "custom_repos_build.sbt")
        )
      end

      before do
        stub_request(:get, "https://oss.sonatype.org/content/repositories/releases/com/google/guava/guava/maven-metadata.xml")
          .to_return(status: 404)
        stub_request(:get, "https://repo.artima.com/releases/com/google/guava/guava/maven-metadata.xml")
          .to_return(status: 404)
      end

      its([:version]) { is_expected.to eq(version_class.new("33.4.0-jre")) }
    end
  end

  describe "#lowest_security_fix_version_details" do
    subject { finder.lowest_security_fix_version_details }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "sbt",
          vulnerable_versions: ["< 33.2.0-jre"]
        )
      ]
    end

    before do
      stub_request(
        :head,
        "https://repo.maven.apache.org/maven2/" \
        "com/google/guava/guava/33.2.0-jre/guava-33.2.0-jre.jar"
      ).to_return(status: 200)
    end

    its([:version]) { is_expected.to eq(version_class.new("33.2.0-jre")) }

    its([:source_url]) do
      is_expected.to eq("https://repo.maven.apache.org/maven2")
    end
  end
end
