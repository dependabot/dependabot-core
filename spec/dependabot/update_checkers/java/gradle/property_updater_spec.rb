# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/java/gradle/property_updater"

RSpec.describe Dependabot::UpdateCheckers::Java::Gradle::PropertyUpdater do
  let(:updater) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      target_version_details: target_version_details,
      ignored_versions: ignored_versions
    )
  end

  let(:version_class) { Dependabot::Utils::Java::Version }
  let(:ignored_versions) { [] }
  let(:target_version_details) do
    {
      version: version_class.new("23.6-jre"),
      source_url: "https://repo.maven.apache.org/maven2"
    }
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "gradle"
    )
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
  let(:dependency_name) { "org.jetbrains.kotlin:kotlin-gradle-plugin" }
  let(:dependency_version) { "1.1.4-3" }
  let(:dependency_files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("java", "buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "shortform_build.gradle" }

  let(:maven_central_metadata_url_gradle_plugin) do
    "https://repo.maven.apache.org/maven2/"\
    "org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml"
  end

  let(:maven_central_metadata_url_stdlib) do
    "https://repo.maven.apache.org/maven2/"\
    "org/jetbrains/kotlin/kotlin-stdlib-jre8/maven-metadata.xml"
  end

  before do
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

  describe "#update_possible?" do
    subject { updater.update_possible? }
    it { is_expected.to eq(true) }

    context "without a target version" do
      let(:target_version_details) { nil }
      it { is_expected.to eq(false) }
    end

    context "when one dependency is missing the target version" do
      before do
        body = fixture("java", "maven_central_metadata", "missing_latest.xml")
        stub_request(:get, maven_central_metadata_url_stdlib).
          to_return(
            status: 200,
            body: body
          )
      end

      it { is_expected.to eq(false) }
    end
  end

  describe "#updated_dependencies" do
    subject(:updated_dependencies) { updater.updated_dependencies }

    it "updates both dependencies" do
      expect(updated_dependencies).to eq(
        [
          Dependabot::Dependency.new(
            name: "org.jetbrains.kotlin:kotlin-gradle-plugin",
            version: "23.6-jre",
            previous_version: "1.1.4-3",
            requirements: [{
              file: "build.gradle",
              requirement: "23.6-jre",
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
            version: "23.6-jre",
            previous_version: "1.1.4-3",
            requirements: [{
              file: "build.gradle",
              requirement: "23.6-jre",
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

    context "when one dependency is missing the target version" do
      before do
        body = fixture("java", "maven_central_metadata", "missing_latest.xml")
        stub_request(:get, maven_central_metadata_url_stdlib).
          to_return(status: 200, body: body)
      end

      specify { expect { updated_dependencies }.to raise_error(/not possible/) }
    end
  end
end
