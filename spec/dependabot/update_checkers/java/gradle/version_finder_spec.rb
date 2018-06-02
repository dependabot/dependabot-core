# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java/gradle/version_finder"

RSpec.describe Dependabot::UpdateCheckers::Java::Gradle::VersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      ignored_versions: ignored_versions
    )
  end
  let(:version_class) { Dependabot::Utils::Java::Version }
  let(:ignored_versions) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "gradle"
    )
  end
  let(:dependency_files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("java", "buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }

  let(:dependency_requirements) do
    [{ file: "pom.xml", requirement: "23.3-jre", groups: [], source: nil }]
  end
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "23.3-jre" }

  let(:maven_central_metadata_url) do
    "https://repo.maven.apache.org/maven2/"\
    "com/google/guava/guava/maven-metadata.xml"
  end
  let(:maven_central_releases) do
    fixture("java", "maven_central_metadata", "with_release.xml")
  end

  before do
    stub_request(:get, maven_central_metadata_url).
      to_return(status: 200, body: maven_central_releases)
  end

  describe "#latest_version_details" do
    subject { finder.latest_version_details }
    its([:version]) { is_expected.to eq(version_class.new("23.6-jre")) }
    its([:source_url]) do
      is_expected.to eq("https://repo.maven.apache.org/maven2")
    end

    context "when the user wants a pre-release" do
      let(:dependency_version) { "23.0-rc1-android" }
      its([:version]) do
        is_expected.to eq(version_class.new("23.7-rc1-android"))
      end
    end

    context "when there are date-based versions" do
      let(:maven_central_releases) do
        fixture("java", "maven_central_metadata", "with_date_releases.xml")
      end
      let(:dependency_version) { "3.1" }
      its([:version]) { is_expected.to eq(version_class.new("3.2.2")) }

      context "and that's what we're using" do
        let(:dependency_version) { "20030418" }
        its([:version]) { is_expected.to eq(version_class.new("20040616")) }
      end
    end

    context "when the user has asked to ignore a major version" do
      let(:ignored_versions) { [">= 23.0, < 24"] }
      let(:dependency_version) { "17.0" }
      its([:version]) { is_expected.to eq(version_class.new("22.0")) }
    end

    context "when the current version isn't normal" do
      let(:dependency_version) { "RELEASE802" }
      its([:version]) { is_expected.to eq(version_class.new("23.0")) }
    end

    context "with a custom repository" do
      let(:buildfile_fixture_name) { "custom_repos_build.gradle" }

      let(:jcenter_metadata_url) do
        "https://jcenter.bintray.com/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:magnusja_metadata_url) do
        "https://dl.bintray.com/magnusja/maven/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:google_metadata_url) do
        "https://maven.google.com/"\
        "com/google/guava/group-index.xml"
      end

      let(:dependency_version) { "18.0.0" }

      before do
        stub_request(:get, jcenter_metadata_url).
          to_return(status: 404, body: "")
        stub_request(:get, magnusja_metadata_url).
          to_raise(Excon::Error::Timeout)
        stub_request(:get, google_metadata_url).
          to_return(
            status: 200,
            body: fixture("java", "google_metadata", "com_google_guava.xml")
          )
      end

      its([:version]) { is_expected.to eq(version_class.new("27.1.1")) }
      its([:source_url]) do
        is_expected.to eq("https://maven.google.com")
      end
    end
  end

  describe "#versions" do
    subject(:versions) { finder.versions }
    its(:count) { is_expected.to eq(70) }

    describe "the first version" do
      subject { versions.first }

      its([:version]) { is_expected.to eq(version_class.new("r03")) }
      its([:source_url]) do
        is_expected.to eq("https://repo.maven.apache.org/maven2")
      end
    end

    describe "the last version" do
      subject { versions.last }

      its([:version]) { is_expected.to eq(version_class.new("23.7-rc1-jre")) }
      its([:source_url]) do
        is_expected.to eq("https://repo.maven.apache.org/maven2")
      end
    end

    context "with a custom repository" do
      let(:buildfile_fixture_name) { "custom_repos_build.gradle" }

      let(:jcenter_metadata_url) do
        "https://jcenter.bintray.com/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:magnusja_metadata_url) do
        "https://dl.bintray.com/magnusja/maven/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:google_metadata_url) do
        "https://maven.google.com/"\
        "com/google/guava/group-index.xml"
      end

      before do
        stub_request(:get, jcenter_metadata_url).
          to_return(status: 404, body: "")
        stub_request(:get, magnusja_metadata_url).
          to_raise(Excon::Error::Timeout)
        stub_request(:get, google_metadata_url).
          to_return(
            status: 200,
            body: fixture("java", "google_metadata", "com_google_guava.xml")
          )
      end

      describe "the first version" do
        subject { versions.first }

        its([:version]) { is_expected.to eq(version_class.new("18.0.0")) }
        its([:source_url]) do
          is_expected.to eq("https://maven.google.com")
        end
      end

      describe "the last version" do
        subject { versions.last }

        its([:version]) do
          is_expected.to eq(version_class.new("28.0.0-alpha1"))
        end
        its([:source_url]) do
          is_expected.to eq("https://maven.google.com")
        end
      end
    end
  end
end
