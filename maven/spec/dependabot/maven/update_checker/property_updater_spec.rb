# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/maven/update_checker/property_updater"

RSpec.describe Dependabot::Maven::UpdateChecker::PropertyUpdater do
  let(:updater) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      target_version_details: target_version_details,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end

  let(:ignored_versions) { [] }
  let(:credentials) { [] }
  let(:version_class) { Dependabot::Maven::Version }
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
      package_manager: "maven"
    )
  end

  let(:dependency_requirements) do
    [{
      file: "pom.xml",
      requirement: "4.3.12.RELEASE",
      groups: [],
      source: nil,
      metadata: {
        property_name: "springframework.version",
        property_source: "pom.xml",
        packaging_type: "jar"
      }
    }]
  end
  let(:dependency_name) { "org.springframework:spring-beans" }
  let(:dependency_version) { "4.3.12.RELEASE" }
  let(:dependency_files) { [pom] }
  let(:pom) do
    Dependabot::DependencyFile.new(name: "pom.xml", content: pom_body)
  end
  let(:pom_body) { fixture("poms", "property_pom.xml") }

  let(:maven_central_metadata_url_beans) do
    "https://repo.maven.apache.org/maven2/" \
      "org/springframework/spring-beans/maven-metadata.xml"
  end

  let(:maven_central_metadata_url_context) do
    "https://repo.maven.apache.org/maven2/" \
      "org/springframework/spring-context/maven-metadata.xml"
  end

  before do
    stub_request(:get, maven_central_metadata_url_beans)
      .to_return(
        status: 200,
        body: fixture("maven_central_metadata", "with_release.xml")
      )
    stub_request(:get, maven_central_metadata_url_context)
      .to_return(
        status: 200,
        body: fixture("maven_central_metadata", "with_release.xml")
      )
  end

  describe "#update_possible?" do
    subject { updater.update_possible? }

    it { is_expected.to be(true) }

    context "without a target version" do
      let(:target_version_details) { nil }

      it { is_expected.to be(false) }
    end

    context "when one dependency is missing the target version" do
      before do
        body = fixture("maven_central_metadata", "missing_latest.xml")
        stub_request(:get, maven_central_metadata_url_context)
          .to_return(
            status: 200,
            body: body
          )
      end

      it { is_expected.to be(false) }
    end

    context "when one dependency uses multiple properties" do
      let(:pom_body) { fixture("poms", "property_pom_suffix.xml") }

      it { is_expected.to be(false) }
    end

    context "when one dependency isn't listed" do
      before do
        stub_request(:get, maven_central_metadata_url_context)
          .to_return(status: 404)
      end

      it { is_expected.to be(true) }
    end
  end

  describe "#updated_dependencies" do
    subject(:updated_dependencies) { updater.updated_dependencies }

    it "updates both dependencies" do
      expect(updated_dependencies).to eq(
        [
          Dependabot::Dependency.new(
            name: "org.springframework:spring-beans",
            version: "23.6-jre",
            previous_version: "4.3.12.RELEASE",
            requirements: [{
              file: "pom.xml",
              requirement: "23.6-jre",
              groups: [],
              source: {
                type: "maven_repo",
                url: "https://repo.maven.apache.org/maven2"
              },
              metadata: {
                property_name: "springframework.version",
                property_source: "pom.xml",
                packaging_type: "jar"
              }
            }],
            previous_requirements: [{
              file: "pom.xml",
              requirement: "4.3.12.RELEASE",
              groups: [],
              source: nil,
              metadata: {
                property_name: "springframework.version",
                property_source: "pom.xml",
                packaging_type: "jar"
              }
            }],
            package_manager: "maven"
          ),
          Dependabot::Dependency.new(
            name: "org.springframework:spring-context",
            version: "23.6-jre",
            previous_version: "4.3.12.RELEASE",
            requirements: [{
              file: "pom.xml",
              requirement: "23.6-jre",
              groups: [],
              source: {
                type: "maven_repo",
                url: "https://repo.maven.apache.org/maven2"
              },
              metadata: {
                property_name: "springframework.version",
                property_source: "pom.xml",
                packaging_type: "jar"
              }
            }],
            previous_requirements: [{
              file: "pom.xml",
              requirement: "4.3.12.RELEASE",
              groups: [],
              source: nil,
              metadata: {
                property_name: "springframework.version",
                property_source: "pom.xml",
                packaging_type: "jar"
              }
            }],
            package_manager: "maven"
          )
        ]
      )
    end

    context "when one dependency is missing the target version" do
      before do
        body = fixture("maven_central_metadata", "missing_latest.xml")
        stub_request(:get, maven_central_metadata_url_context)
          .to_return(status: 200, body: body)
      end

      specify { expect { updated_dependencies }.to raise_error(/not possible/) }
    end

    context "when one dependency has other declarations" do
      let(:pom_body) do
        fixture("poms", "repeated_multi_property_pom2.xml")
      end

      let(:dependency_requirements) do
        [{
          file: "pom.xml",
          requirement: "1.0.0-M2",
          groups: ["test"],
          source: nil,
          metadata: {
            property_name: "junit-platform.version",
            property_source: "pom.xml",
            packaging_type: "jar"
          }
        }]
      end
      let(:dependency_name) do
        "org.junit.platform:junit-platform-surefire-provider"
      end
      let(:dependency_version) { "1.0.0-M2" }

      let(:maven_central_metadata_url_runner) do
        "https://repo.maven.apache.org/maven2/" \
          "org/junit/platform/junit-platform-runner/maven-metadata.xml"
      end

      let(:maven_central_metadata_url_surefire_provider) do
        "https://repo.maven.apache.org/maven2/" \
          "org/junit/platform/junit-platform-surefire-provider/maven-metadata.xml"
      end

      before do
        stub_request(:get, maven_central_metadata_url_runner)
          .to_return(
            status: 200,
            body: fixture("maven_central_metadata", "with_release.xml")
          )
        stub_request(:get, maven_central_metadata_url_surefire_provider)
          .to_return(
            status: 200,
            body: fixture("maven_central_metadata", "with_release.xml")
          )
      end

      it "updates both dependencies" do
        expect(updated_dependencies).to eq(
          [
            Dependabot::Dependency.new(
              name: "org.junit.platform:junit-platform-runner",
              version: "23.6-jre",
              previous_version: "1.0.0-M2",
              requirements: [{
                file: "pom.xml",
                requirement: nil,
                groups: [],
                source: nil,
                metadata: { packaging_type: "jar" }
              }, {
                file: "pom.xml",
                requirement: "23.6-jre",
                groups: ["test"],
                source: {
                  type: "maven_repo",
                  url: "https://repo.maven.apache.org/maven2"
                },
                metadata: {
                  property_name: "junit-platform.version",
                  property_source: "pom.xml",
                  packaging_type: "jar"
                }
              }, {
                file: "pom.xml",
                requirement: "1.0.0",
                groups: [],
                source: nil,
                metadata: {
                  property_name: "another.version",
                  property_source: "pom.xml",
                  packaging_type: "jar"
                }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: nil,
                groups: [],
                source: nil,
                metadata: { packaging_type: "jar" }
              }, {
                file: "pom.xml",
                requirement: "1.0.0-M2",
                groups: ["test"],
                source: nil,
                metadata: {
                  property_name: "junit-platform.version",
                  property_source: "pom.xml",
                  packaging_type: "jar"
                }
              }, {
                file: "pom.xml",
                requirement: "1.0.0",
                groups: [],
                source: nil,
                metadata: {
                  property_name: "another.version",
                  property_source: "pom.xml",
                  packaging_type: "jar"
                }
              }],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "org.junit.platform:junit-platform-surefire-provider",
              version: "23.6-jre",
              previous_version: "1.0.0-M2",
              requirements: [{
                file: "pom.xml",
                requirement: "23.6-jre",
                groups: [],
                source: {
                  type: "maven_repo",
                  url: "https://repo.maven.apache.org/maven2"
                },
                metadata: {
                  property_name: "junit-platform.version",
                  property_source: "pom.xml",
                  packaging_type: "jar"
                }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "1.0.0-M2",
                groups: [],
                source: nil,
                metadata: {
                  property_name: "junit-platform.version",
                  property_source: "pom.xml",
                  packaging_type: "jar"
                }
              }],
              package_manager: "maven"
            )
          ]
        )
      end
    end
  end
end
