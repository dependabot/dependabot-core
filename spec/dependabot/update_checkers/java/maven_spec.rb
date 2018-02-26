# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java/maven"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Java::Maven do
  it_behaves_like "an update checker"

  let(:maven_central_metadata_url) do
    "https://search.maven.org/remotecontent?filepath="\
    "com/google/guava/guava/maven-metadata.xml"
  end

  before do
    stub_request(:get, maven_central_metadata_url).
      to_return(
        status: 200,
        body: fixture("java", "maven_central_metadata", "with_release.xml")
      )
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end
  let(:dependency_files) { [pom] }
  let(:credentials) { [] }
  let(:pom) do
    Dependabot::DependencyFile.new(name: "pom.xml", content: pom_body)
  end
  let(:pom_body) { fixture("java", "poms", "basic_pom.xml") }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "maven"
    )
  end
  let(:dependency_requirements) do
    [{ file: "pom.xml", requirement: "23.3-jre", groups: [], source: nil }]
  end
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "23.3-jre" }

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(described_class::Version.new("23.6-jre")) }

    context "when Maven Central doesn't return a release tag" do
      before do
        stub_request(:get, maven_central_metadata_url).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "no_release.xml")
          )
      end

      it { is_expected.to eq(described_class::Version.new("23.6-jre")) }
    end

    context "when the user doesn't want a pre-release" do
      let(:dependency_version) { "18.0" }

      it { is_expected.to eq(described_class::Version.new("23.0")) }
    end

    context "when the version comes from a property" do
      let(:pom_body) { fixture("java", "poms", "property_pom_single.xml") }
      let(:maven_central_metadata_url) do
        "https://search.maven.org/remotecontent?filepath="\
        "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:dependency_requirements) do
        [
          {
            file: "pom.xml",
            requirement: "4.3.12.RELEASE",
            groups: [],
            source: nil
          }
        ]
      end
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:dependency_version) { "4.3.12.RELEASE" }

      it { is_expected.to eq(described_class::Version.new("23.6-jre")) }

      context "that affects multiple dependencies" do
        let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
        it { is_expected.to eq(described_class::Version.new("23.6-jre")) }
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }
    it { is_expected.to eq(described_class::Version.new("23.6-jre")) }

    context "when the version comes from a property" do
      let(:pom_body) { fixture("java", "poms", "property_pom_single.xml") }
      let(:maven_central_metadata_url) do
        "https://search.maven.org/remotecontent?filepath="\
        "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:dependency_requirements) do
        [
          {
            file: "pom.xml",
            requirement: "4.3.12.RELEASE",
            groups: [],
            source: nil
          }
        ]
      end
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:dependency_version) { "4.3.12.RELEASE" }

      it { is_expected.to eq(described_class::Version.new("23.6-jre")) }

      context "that affects multiple dependencies" do
        let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
        it { is_expected.to be_nil }
      end
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    before do
      allow(checker).
        to receive(:latest_version).
        and_return(described_class::Version.new("23.6-jre"))
    end

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: dependency_requirements,
          latest_version: "23.6-jre"
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [
            {
              file: "pom.xml",
              requirement: "23.6-jre",
              groups: [],
              source: nil
            }
          ]
        )
    end
  end

  describe "#latest_version_resolvable_with_full_unlock?" do
    subject { checker.send(:latest_version_resolvable_with_full_unlock?) }

    context "with no latest version" do
      before { allow(checker).to receive(:latest_version).and_return(nil) }
      it { is_expected.to be_falsey }
    end

    context "with a non-property pom" do
      let(:pom_body) { fixture("java", "poms", "basic_pom.xml") }
      it { is_expected.to be_falsey }
    end

    context "with a property pom" do
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
      let(:maven_central_metadata_url_beans) do
        "https://search.maven.org/remotecontent?filepath="\
        "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_context) do
        "https://search.maven.org/remotecontent?filepath="\
        "org/springframework/spring-context/maven-metadata.xml"
      end

      before do
        allow(checker).
          to receive(:latest_version).
          and_return(described_class::Version.new("23.6-jre"))
        stub_request(:get, maven_central_metadata_url_beans).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, maven_central_metadata_url_context).
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
            target_version: described_class::Version.new("23.6-jre")
          ).
          and_call_original
        expect(subject).to eq(true)
      end
    end
  end

  describe "#updated_dependencies_after_full_unlock" do
    subject { checker.send(:updated_dependencies_after_full_unlock) }

    context "with a property pom" do
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
      let(:maven_central_metadata_url_beans) do
        "https://search.maven.org/remotecontent?filepath="\
        "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_context) do
        "https://search.maven.org/remotecontent?filepath="\
        "org/springframework/spring-context/maven-metadata.xml"
      end

      before do
        allow(checker).
          to receive(:latest_version).
          and_return(described_class::Version.new("23.6-jre"))
        stub_request(:get, maven_central_metadata_url_beans).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, maven_central_metadata_url_context).
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
            target_version: described_class::Version.new("23.6-jre")
          ).
          and_call_original
        expect(subject).to eq(
          [
            Dependabot::Dependency.new(
              name: "org.springframework:spring-beans",
              version: "23.6-jre",
              previous_version: "4.3.12.RELEASE",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "23.6-jre",
                  groups: [],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE",
                  groups: [],
                  source: nil
                }
              ],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "org.springframework:spring-context",
              version: "23.6-jre",
              previous_version: "4.3.12.RELEASE",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "23.6-jre",
                  groups: [],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE",
                  groups: [],
                  source: nil
                }
              ],
              package_manager: "maven"
            )
          ]
        )
      end
    end
  end
end
