# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java/gradle"
require "dependabot/utils/java/version"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Java::Gradle do
  it_behaves_like "an update checker"

  let(:maven_central_metadata_url) do
    "https://repo.maven.apache.org/maven2/"\
    "com/google/guava/guava/maven-metadata.xml"
  end
  let(:version_class) { Dependabot::Utils::Java::Version }
  let(:maven_central_releases) do
    fixture("java", "maven_central_metadata", "with_release.xml")
  end

  before do
    stub_request(:get, maven_central_metadata_url).
      to_return(status: 200, body: maven_central_releases)
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end
  let(:dependency_files) { [buildfile] }
  let(:credentials) { [] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("java", "buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "gradle"
    )
  end
  let(:dependency_requirements) do
    [{ file: "build.gradle", requirement: "23.3-jre", groups: [], source: nil }]
  end
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "23.3-jre" }

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(version_class.new("23.6-jre")) }

    context "when Maven Central doesn't return a release tag" do
      let(:maven_central_releases) do
        fixture("java", "maven_central_metadata", "no_release.xml")
      end

      it { is_expected.to eq(version_class.new("23.6-jre")) }
    end

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
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }
    it { is_expected.to eq(version_class.new("23.6-jre")) }
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    before do
      allow(checker).
        to receive(:latest_version).
        and_return(version_class.new("23.6-jre"))
    end

    it "delegates to the RequirementsUpdater" do
      expect(Dependabot::UpdateCheckers::Java::Maven::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: dependency_requirements,
          latest_version: "23.6-jre",
          source_url: "https://repo.maven.apache.org/maven2"
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [
            {
              file: "build.gradle",
              requirement: "23.6-jre",
              groups: [],
              source: {
                type: "maven_repo",
                url: "https://repo.maven.apache.org/maven2"
              }
            }
          ]
        )
    end
  end

  describe "#up_to_date?" do
    subject { checker.up_to_date? }

    context "when the current version isn't normal" do
      let(:dependency_version) { "RELEASE802" }
      it { is_expected.to eq(false) }
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :all) }

    context "when the current version isn't normal" do
      let(:dependency_version) { "RELEASE802" }
      it { is_expected.to eq(false) }
    end
  end
end
