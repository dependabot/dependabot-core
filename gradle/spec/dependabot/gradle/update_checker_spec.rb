# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/gradle/update_checker"
require "dependabot/gradle/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Gradle::UpdateChecker do
  it_behaves_like "an update checker"

  let(:maven_central_metadata_url) do
    "https://repo.maven.apache.org/maven2/" \
      "com/google/guava/guava/maven-metadata.xml"
  end
  let(:version_class) { Dependabot::Gradle::Version }
  let(:maven_central_releases) do
    fixture("maven_central_metadata", "with_release.xml")
  end

  before do
    stub_request(:get, maven_central_metadata_url).
      to_return(status: 200, body: maven_central_releases)
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )
  end
  let(:dependency_files) { [buildfile] }
  let(:credentials) { [] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }

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
        fixture("maven_central_metadata", "no_release.xml")
      end

      it { is_expected.to eq(version_class.new("23.6-jre")) }
    end

    context "when the user wants a pre-release" do
      let(:dependency_version) { "23.0-rc1-android" }
      it { is_expected.to eq(version_class.new("23.7-rc1-android")) }
    end

    context "when there are date-based versions" do
      let(:maven_central_releases) do
        fixture("maven_central_metadata", "with_date_releases.xml")
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
        "https://repo.maven.apache.org/maven2/" \
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
      let(:dependency_name) { "org.jetbrains.kotlin:kotlin-stdlib-jre8" }
      let(:dependency_version) { "1.1.4-3" }

      it { is_expected.to eq(version_class.new("23.0")) }

      context "that affects multiple dependencies" do
        let(:buildfile_fixture_name) { "shortform_build.gradle" }
        it { is_expected.to eq(version_class.new("23.0")) }
      end
    end

    context "when the dependency comes from a dependency set" do
      let(:buildfile_fixture_name) { "dependency_set.gradle" }
      let(:maven_central_metadata_url) do
        "https://jcenter.bintray.com/" \
          "com/google/protobuf/protoc/maven-metadata.xml"
      end
      let(:dependency_requirements) do
        [{
          file: "build.gradle",
          requirement: "3.6.1",
          groups: [],
          source: nil,
          metadata: {
            dependency_set: { group: "com.google.protobuf", version: "3.6.1" }
          }
        }]
      end
      let(:dependency_name) { "com.google.protobuf:protoc" }
      let(:dependency_version) { "3.6.1" }

      it { is_expected.to eq(version_class.new("23.0")) }
    end

    context "with a git source" do
      let(:dependency_requirements) do
        [{
          file: "build.gradle",
          requirement: nil,
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/heremaps/oksse.git",
            branch: nil
          }
        }]
      end
      let(:dependency_name) { "com.github.heremaps:oksse" }
      let(:dependency_version) { "af885e2e890b9ef0875edd2b117305119ee5bdc5" }

      it { is_expected.to be_nil }
    end
  end

  describe "#lowest_security_fix_version" do
    subject { checker.lowest_security_fix_version }

    it "finds the lowest available non-vulnerable version" do
      is_expected.to eq(version_class.new("23.4-jre"))
    end

    context "with a security vulnerability" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "gradle",
            vulnerable_versions: ["< 23.5.0"]
          )
        ]
      end

      it "finds the lowest available non-vulnerable version" do
        is_expected.to eq(version_class.new("23.5-jre"))
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }
    it { is_expected.to eq(version_class.new("23.6-jre")) }

    context "when the version comes from a property" do
      let(:buildfile_fixture_name) { "single_property_build.gradle" }
      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/" \
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
      let(:dependency_name) { "org.jetbrains.kotlin:kotlin-stdlib-jre8" }
      let(:dependency_version) { "1.1.4-3" }

      it { is_expected.to eq(version_class.new("23.0")) }

      context "that affects multiple dependencies" do
        let(:buildfile_fixture_name) { "shortform_build.gradle" }
        it { is_expected.to be_nil }
      end
    end

    context "when the dependency comes from a dependency set" do
      let(:buildfile_fixture_name) { "dependency_set.gradle" }
      let(:maven_central_metadata_url) do
        "https://jcenter.bintray.com/" \
          "com/google/protobuf/protoc/maven-metadata.xml"
      end
      let(:dependency_requirements) do
        [{
          file: "build.gradle",
          requirement: "3.6.1",
          groups: [],
          source: nil,
          metadata: {
            dependency_set: { group: "com.google.protobuf", version: "3.6.1" }
          }
        }]
      end
      let(:dependency_name) { "com.google.protobuf:protoc" }
      let(:dependency_version) { "3.6.1" }

      it { is_expected.to be_nil }
    end
  end

  describe "#preferred_resolvable_version" do
    subject { checker.preferred_resolvable_version }
    it { is_expected.to eq(version_class.new("23.6-jre")) }

    context "with a security vulnerability" do
      let(:dependency_version) { "18.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "rails",
            package_manager: "gradle",
            safe_versions: ["> 19.0"]
          )
        ]
      end

      it { is_expected.to eq(version_class.new("20.0")) }
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
      expect(described_class::RequirementsUpdater).
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

    context "with a security vulnerability" do
      let(:dependency_version) { "18.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "rails",
            package_manager: "gradle",
            safe_versions: ["> 19.0"]
          )
        ]
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            latest_version: "20.0",
            source_url: "https://repo.maven.apache.org/maven2",
            properties_to_update: []
          ).
          and_call_original
        expect(checker.updated_requirements).
          to eq(
            [{
              file: "build.gradle",
              requirement: "20.0",
              groups: [],
              source: {
                type: "maven_repo",
                url: "https://repo.maven.apache.org/maven2"
              }
            }]
          )
      end
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
        "https://repo.maven.apache.org/maven2/" \
          "org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_stdlib) do
        "https://repo.maven.apache.org/maven2/" \
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
            body: fixture("maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, maven_central_metadata_url_stdlib).
          to_return(
            status: 200,
            body: fixture("maven_central_metadata", "with_release.xml")
          )
      end

      it "delegates to the MultiDependencyUpdater" do
        expect(described_class::MultiDependencyUpdater).
          to receive(:new).
          with(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: [],
            raise_on_ignored: false,
            target_version_details: {
              version: version_class.new("23.0"),
              source_url: "https://repo.maven.apache.org/maven2"
            }
          ).
          and_call_original
        expect(subject).to eq(true)
      end
    end

    context "when the dependency comes from a dependency set" do
      let(:buildfile_fixture_name) { "dependency_set.gradle" }
      let(:dependency_requirements) do
        [{
          file: "build.gradle",
          requirement: "3.6.1",
          groups: [],
          source: nil,
          metadata: {
            dependency_set: { group: "com.google.protobuf", version: "3.6.1" }
          }
        }]
      end
      let(:dependency_name) { "com.google.protobuf:protoc" }
      let(:dependency_version) { "3.6.1" }

      let(:jcenter_metadata_url_protoc) do
        "https://jcenter.bintray.com/" \
          "com/google/protobuf/protoc/maven-metadata.xml"
      end
      let(:jcenter_metadata_url_protobuf_java) do
        "https://jcenter.bintray.com/" \
          "com/google/protobuf/protobuf-java/maven-metadata.xml"
      end
      let(:jcenter_metadata_url_protobuf_java_util) do
        "https://jcenter.bintray.com/" \
          "com/google/protobuf/protobuf-java-util/maven-metadata.xml"
      end

      before do
        stub_request(:get, jcenter_metadata_url_protoc).
          to_return(
            status: 200,
            body: fixture("maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, jcenter_metadata_url_protobuf_java).
          to_return(
            status: 200,
            body: fixture("maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, jcenter_metadata_url_protobuf_java_util).
          to_return(
            status: 200,
            body: fixture("maven_central_metadata", "with_release.xml")
          )
      end

      it "delegates to the MultiDependencyUpdater" do
        expect(described_class::MultiDependencyUpdater).
          to receive(:new).
          with(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: [],
            raise_on_ignored: false,
            target_version_details: {
              version: version_class.new("23.0"),
              source_url: "https://jcenter.bintray.com"
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
        "https://repo.maven.apache.org/maven2/" \
          "org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_stdlib) do
        "https://repo.maven.apache.org/maven2/" \
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
            body: fixture("maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, maven_central_metadata_url_stdlib).
          to_return(
            status: 200,
            body: fixture("maven_central_metadata", "with_release.xml")
          )
      end

      it "delegates to the MultiDependencyUpdater" do
        expect(described_class::MultiDependencyUpdater).
          to receive(:new).
          with(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: [],
            raise_on_ignored: false,
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

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    let(:buildfile_fixture_name) { "version_range_dependency.gradle" }
    let(:dependency_name) { "junit:junit" }
    let(:dependency_version) { nil }
    let(:dependency_requirements) do
      [{
        file: "gradle.build",
        requirement: "4.+",
        groups: [],
        source: nil,
        metadata: nil
      }]
    end

    it { is_expected.to eq(true) }
  end
end
