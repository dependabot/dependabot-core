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
      let(:dependency_version) { "23.0-rc1-android" }
      it { is_expected.to eq(version_class.new("23.7-rc1-android")) }
    end

    context "when there are date-based versions" do
      let(:maven_central_releases) do
        fixture("java", "maven_central_metadata", "with_date_releases.xml")
      end
      let(:dependency_version) { "3.1" }
      it { is_expected.to eq(version_class.new("3.2.2")) }

      context "and that's what we're using" do
        let(:dependency_version) { "20030418" }
        it { is_expected.to eq(version_class.new("20040616")) }
      end
    end

    context "when the current version isn't normal" do
      let(:dependency_version) { "RELEASE802" }
      it { is_expected.to eq(version_class.new("23.0")) }
    end

    context "when the version comes from a property" do
      let(:buildfile_fixture_name) { "single_property_build.gradle" }
      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/"\
        "org/jetbrains/kotlin/kotlin-stdlib-jre8/maven-metadata.xml"
      end
      let(:dependency_requirements) do
        [{
          file: "pom.xml",
          requirement: "1.1.4-3",
          groups: [],
          source: nil,
          metadata: { property_name: "kotlin_version" }
        }]
      end
      let(:dependency_name) { "org.jetbrains.kotlin:kotlin-stdlib-jre8" }
      let(:dependency_version) { "1.1.4-3" }

      it { is_expected.to eq(version_class.new("23.0")) }

      context "that affects multiple dependencies" do
        let(:buildfile_fixture_name) { "shortform_build.gradle" }
        it { is_expected.to eq(version_class.new("23.0")) }
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }
    it { is_expected.to eq(version_class.new("23.6-jre")) }

    context "when the version comes from a property" do
      let(:buildfile_fixture_name) { "single_property_build.gradle" }
      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/"\
        "org/jetbrains/kotlin/kotlin-stdlib-jre8/maven-metadata.xml"
      end
      let(:dependency_requirements) do
        [{
          file: "pom.xml",
          requirement: "1.1.4-3",
          groups: [],
          source: nil,
          metadata: { property_name: "kotlin_version" }
        }]
      end
      let(:dependency_name) { "org.jetbrains.kotlin:kotlin-stdlib-jre8" }
      let(:dependency_version) { "1.1.4-3" }

      it { is_expected.to eq(version_class.new("23.0")) }

      context "that affects multiple dependencies" do
        let(:buildfile_fixture_name) { "shortform_build.gradle" }
        it { is_expected.to be_nil }
      end
    end
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
          source_url: "https://repo.maven.apache.org/maven2",
          properties_to_update: []
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [{
            file: "build.gradle",
            requirement: "23.6-jre",
            groups: [],
            source: {
              type: "maven_repo",
              url: "https://repo.maven.apache.org/maven2"
            }
          }]
        )
    end
  end

  describe "#latest_version_resolvable_with_full_unlock?" do
    subject { checker.send(:latest_version_resolvable_with_full_unlock?) }

    context "with no latest version" do
      before { allow(checker).to receive(:latest_version).and_return(nil) }
      it { is_expected.to be_falsey }
    end

    context "with a non-property buildfile" do
      let(:buildfile_fixture_name) { "basic_build.gradle" }
      it { is_expected.to be_falsey }
    end

    context "with a property buildfile" do
      let(:dependency_name) { "org.jetbrains.kotlin:kotlin-gradle-plugin" }
      let(:buildfile_fixture_name) { "shortform_build.gradle" }
      let(:dependency_version) { "1.1.4-3" }
      let(:maven_central_metadata_url_gradle_plugin) do
        "https://repo.maven.apache.org/maven2/"\
        "org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_stdlib) do
        "https://repo.maven.apache.org/maven2/"\
        "org/jetbrains/kotlin/kotlin-stdlib-jre8/maven-metadata.xml"
      end
      let(:dependency_requirements) do
        [{
          file: "build.gradle",
          requirement: "1.1.4-3",
          groups: [],
          source: nil,
          metadata: { property_name: "kotlin_version" }
        }]
      end

      before do
        allow(checker).
          to receive(:latest_version).
          and_return(version_class.new("23.6-jre"))
        stub_request(:get, maven_central_metadata_url_gradle_plugin).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, maven_central_metadata_url_stdlib).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "with_release.xml")
          )
      end

      it "delegates to the PropertyUpdater" do
        expect(described_class::PropertyUpdater).
          to receive(:new).
          with(
            dependency: dependency,
            dependency_files: dependency_files,
            ignored_versions: [],
            target_version_details: {
              version: version_class.new("23.0"),
              source_url: "https://repo.maven.apache.org/maven2"
            }
          ).
          and_call_original
        expect(subject).to eq(true)
      end
    end
  end

  describe "#updated_dependencies_after_full_unlock" do
    subject { checker.send(:updated_dependencies_after_full_unlock) }

    context "with a property buildfile" do
      let(:dependency_name) { "org.jetbrains.kotlin:kotlin-gradle-plugin" }
      let(:buildfile_fixture_name) { "shortform_build.gradle" }
      let(:dependency_version) { "1.1.4-3" }
      let(:maven_central_metadata_url_gradle_plugin) do
        "https://repo.maven.apache.org/maven2/"\
        "org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_stdlib) do
        "https://repo.maven.apache.org/maven2/"\
        "org/jetbrains/kotlin/kotlin-stdlib-jre8/maven-metadata.xml"
      end
      let(:dependency_requirements) do
        [{
          file: "build.gradle",
          requirement: "1.1.4-3",
          groups: [],
          source: nil,
          metadata: { property_name: "kotlin_version" }
        }]
      end

      before do
        allow(checker).
          to receive(:latest_version).
          and_return(version_class.new("23.6-jre"))
        stub_request(:get, maven_central_metadata_url_gradle_plugin).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, maven_central_metadata_url_stdlib).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "with_release.xml")
          )
      end

      it "delegates to the PropertyUpdater" do
        expect(described_class::PropertyUpdater).
          to receive(:new).
          with(
            dependency: dependency,
            dependency_files: dependency_files,
            ignored_versions: [],
            target_version_details: {
              version: version_class.new("23.0"),
              source_url: "https://repo.maven.apache.org/maven2"
            }
          ).
          and_call_original
        expect(subject).to eq(
          [
            Dependabot::Dependency.new(
              name: "org.jetbrains.kotlin:kotlin-gradle-plugin",
              version: "23.0",
              previous_version: "1.1.4-3",
              requirements: [{
                file: "build.gradle",
                requirement: "23.0",
                groups: [],
                source: {
                  type: "maven_repo",
                  url: "https://repo.maven.apache.org/maven2"
                },
                metadata: { property_name: "kotlin_version" }
              }],
              previous_requirements: [{
                file: "build.gradle",
                requirement: "1.1.4-3",
                groups: [],
                source: nil,
                metadata: { property_name: "kotlin_version" }
              }],
              package_manager: "gradle"
            ),
            Dependabot::Dependency.new(
              name: "org.jetbrains.kotlin:kotlin-stdlib-jre8",
              version: "23.0",
              previous_version: "1.1.4-3",
              requirements: [{
                file: "build.gradle",
                requirement: "23.0",
                groups: [],
                source: {
                  type: "maven_repo",
                  url: "https://repo.maven.apache.org/maven2"
                },
                metadata: { property_name: "kotlin_version" }
              }],
              previous_requirements: [{
                file: "build.gradle",
                requirement: "1.1.4-3",
                groups: [],
                source: nil,
                metadata: { property_name: "kotlin_version" }
              }],
              package_manager: "gradle"
            )
          ]
        )
      end
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
