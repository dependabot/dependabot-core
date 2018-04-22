# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java/maven/version_finder"

RSpec.describe Dependabot::UpdateCheckers::Java::Maven::VersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files
    )
  end
  let(:version_class) { Dependabot::Utils::Java::Version }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "maven"
    )
  end
  let(:dependency_files) { [pom] }
  let(:pom) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: fixture("java", "poms", pom_fixture_name)
    )
  end
  let(:pom_fixture_name) { "basic_pom.xml" }

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

  describe "#latest_version" do
    subject { finder.latest_version }
    it { is_expected.to eq(version_class.new("23.6-jre")) }

    context "when the user wants a pre-release" do
      let(:dependency_version) { "18.0-beta" }
      it { is_expected.to eq(version_class.new("23.7-jre-rc1")) }
    end

    context "when there are date-based versions" do
      let(:maven_central_releases) do
        fixture("java", "maven_central_metadata", "with_date_releases.xml")
      end
      it { is_expected.to eq(version_class.new("3.2.2")) }

      context "and that's what we're using" do
        let(:dependency_version) { "20030418" }
        it { is_expected.to eq(version_class.new("20040616")) }
      end
    end

    context "when the current version isn't normal" do
      let(:dependency_version) { "RELEASE802" }
      it { is_expected.to eq(version_class.new("23.6-jre")) }
    end

    context "with a custom repository" do
      let(:pom_fixture_name) { "custom_repositories_pom.xml" }

      let(:scala_tools_metadata_url) do
        "http://scala-tools.org/repo-releases/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:jboss_metadata_url) do
        "http://repository.jboss.org/maven2/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:jboss_plugins_metadata_url) do
        "http://plugin-repository.jboss.org/maven2/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      before do
        stub_request(:get, maven_central_metadata_url).
          to_return(status: 404, body: "")
        stub_request(:get, scala_tools_metadata_url).
          to_return(status: 404, body: "")
        stub_request(:get, jboss_metadata_url).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, jboss_plugins_metadata_url).
          to_return(status: 404, body: "")
      end

      it { is_expected.to eq(version_class.new("23.6-jre")) }
    end
  end

  describe "#versions" do
    subject { finder.versions }
    its(:count) { is_expected.to eq(63) }
    its(:first) { is_expected.to eq(version_class.new("10.0-rc1")) }
    its(:last) { is_expected.to eq(version_class.new("23.7-jre-rc1")) }

    context "with a custom repository" do
      let(:pom_fixture_name) { "custom_repositories_pom.xml" }

      let(:scala_tools_metadata_url) do
        "http://scala-tools.org/repo-releases/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:jboss_metadata_url) do
        "http://repository.jboss.org/maven2/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:jboss_plugins_metadata_url) do
        "http://plugin-repository.jboss.org/maven2/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      before do
        stub_request(:get, maven_central_metadata_url).
          to_return(status: 404, body: "")
        stub_request(:get, scala_tools_metadata_url).
          to_return(status: 404, body: "")
        stub_request(:get, jboss_metadata_url).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, jboss_plugins_metadata_url).
          to_return(status: 404, body: "")
      end

      its(:first) { is_expected.to eq(version_class.new("10.0-rc1")) }
      its(:last) { is_expected.to eq(version_class.new("23.7-jre-rc1")) }

      context "that augment the central repo" do
        before do
          body =
            fixture("java", "maven_central_metadata", "with_date_releases.xml")
          stub_request(:get, maven_central_metadata_url).
            to_return(status: 200, body: body)
        end

        its(:count) { is_expected.to eq(80) }
        its(:first) { is_expected.to eq(version_class.new("1.0")) }
        its(:last) { is_expected.to eq(version_class.new("20040616")) }
      end
    end
  end
end
