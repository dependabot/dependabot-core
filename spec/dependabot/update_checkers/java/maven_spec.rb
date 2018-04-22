# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java/maven"
require "dependabot/utils/java/version"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Java::Maven do
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

    context "when the version comes from a property" do
      let(:pom_body) { fixture("java", "poms", "property_pom_single.xml") }
      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/"\
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

      it { is_expected.to eq(version_class.new("23.6-jre")) }

      context "that affects multiple dependencies" do
        let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
        it { is_expected.to eq(version_class.new("23.6-jre")) }
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }
    it { is_expected.to eq(version_class.new("23.6-jre")) }

    context "when the version comes from a property" do
      let(:pom_body) { fixture("java", "poms", "property_pom_single.xml") }
      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/"\
        "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:dependency_requirements) do
        [{
          file: "pom.xml",
          requirement: "4.3.12.RELEASE",
          groups: [],
          source: nil
        }]
      end
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:dependency_version) { "4.3.12.RELEASE" }

      it { is_expected.to eq(version_class.new("23.6-jre")) }

      context "that affects multiple dependencies" do
        let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
        it { is_expected.to be_nil }
      end

      context "for a repeated dependency" do
        let(:pom_body) { fixture("java", "poms", "repeated_pom.xml") }
        let(:maven_central_metadata_url) do
          "https://repo.maven.apache.org/maven2/"\
          "org/apache/maven/plugins/maven-javadoc-plugin/maven-metadata.xml"
        end
        let(:dependency_name) do
          "org.apache.maven.plugins:maven-javadoc-plugin"
        end
        let(:dependency_requirements) do
          [
            {
              file: "pom.xml",
              requirement: "3.0.0-M1",
              groups: [],
              source: nil
            },
            {
              file: "pom.xml",
              requirement: "2.10.4",
              groups: [],
              source: nil
            }
          ]
        end
        it { is_expected.to eq(version_class.new("23.6-jre")) }

        context "that affects multiple dependencies" do
          let(:pom_body) do
            fixture("java", "poms", "repeated_multi_property_pom.xml")
          end
          it { is_expected.to be_nil }
        end

        context "with a nil requirement" do
          let(:dependency_requirements) do
            [
              {
                file: "pom.xml",
                requirement: "3.0.0-M1",
                groups: [],
                source: nil
              },
              {
                file: "pom.xml",
                requirement: nil,
                groups: [],
                source: nil
              }
            ]
          end
          it { is_expected.to eq(version_class.new("23.6-jre")) }
        end
      end
    end

    context "with a multimodule pom" do
      let(:dependency_files) do
        [
          multimodule_pom, util_pom, business_app_pom, legacy_pom, webapp_pom,
          some_spring_project_pom
        ]
      end
      let(:multimodule_pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("java", "poms", "multimodule_pom.xml")
        )
      end
      let(:util_pom) do
        Dependabot::DependencyFile.new(
          name: "util/pom.xml",
          content: fixture("java", "poms", "util_pom.xml")
        )
      end
      let(:business_app_pom) do
        Dependabot::DependencyFile.new(
          name: "business-app/pom.xml",
          content: fixture("java", "poms", "business_app_pom.xml")
        )
      end
      let(:legacy_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/pom.xml",
          content: fixture("java", "poms", "legacy_pom.xml")
        )
      end
      let(:webapp_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/webapp/pom.xml",
          content: fixture("java", "poms", "webapp_pom.xml")
        )
      end
      let(:some_spring_project_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/some-spring-project/pom.xml",
          content: fixture("java", "poms", "some_spring_project_pom.xml")
        )
      end

      context "for a dependency inherited by others" do
        let(:dependency_requirements) do
          [
            {
              requirement: "23.0-jre",
              file: "pom.xml",
              groups: [],
              source: nil
            },
            {
              requirement: nil,
              file: "util/pom.xml",
              groups: [],
              source: nil
            }
          ]
        end
        let(:dependency_name) { "com.google.guava:guava" }
        let(:dependency_version) { "23.0-jre" }

        it { is_expected.to eq(version_class.new("23.6-jre")) }
      end

      context "for a dependency that uses a property from its parent" do
        let(:dependency_requirements) do
          [
            {
              requirement: "2.5.6",
              file: "legacy/some-spring-project/pom.xml",
              groups: [],
              source: nil
            }
          ]
        end
        let(:dependency_name) { "org.springframework:spring-aop" }
        let(:dependency_version) { "2.5.6" }
        let(:maven_central_metadata_url) do
          "https://repo.maven.apache.org/maven2/"\
          "org/springframework/spring-aop/maven-metadata.xml"
        end

        it { is_expected.to eq(version_class.new("23.6-jre")) }
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
      expect(described_class::RequirementsUpdater).
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
              file: "pom.xml",
              requirement: "23.6-jre",
              groups: [],
              source: { url: "https://repo.maven.apache.org/maven2" }
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
        "https://repo.maven.apache.org/maven2/"\
        "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_context) do
        "https://repo.maven.apache.org/maven2/"\
        "org/springframework/spring-context/maven-metadata.xml"
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

      before do
        allow(checker).
          to receive(:latest_version).
          and_return(version_class.new("23.6-jre"))
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
            target_version_details: {
              version: version_class.new("23.6-jre"),
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

    context "with a property pom" do
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
      let(:maven_central_metadata_url_beans) do
        "https://repo.maven.apache.org/maven2/"\
        "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_context) do
        "https://repo.maven.apache.org/maven2/"\
        "org/springframework/spring-context/maven-metadata.xml"
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

      before do
        allow(checker).
          to receive(:latest_version).
          and_return(version_class.new("23.6-jre"))
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
            target_version_details: {
              version: version_class.new("23.6-jre"),
              source_url: "https://repo.maven.apache.org/maven2"
            }
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
                  source: { url: "https://repo.maven.apache.org/maven2" }
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
              version: "23.6-jre.1",
              previous_version: "4.3.12.RELEASE.1",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "23.6-jre.1",
                  groups: [],
                  source: { url: "https://repo.maven.apache.org/maven2" }
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE.1",
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

    context "with a basic POM" do
      let(:pom_body) { fixture("java", "poms", "basic_pom.xml") }
      it { is_expected.to eq(true) }
    end

    context "with a property POM" do
      let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
      let(:dependency_name) { "org.springframework:spring-context" }
      let(:dependency_version) { "4.3.12.RELEASE.1" }
      let(:dependency_requirements) do
        [{
          file: "pom.xml",
          requirement: "4.3.12.RELEASE.1",
          groups: [],
          source: nil
        }]
      end
      it { is_expected.to eq(true) }

      context "that inherits from a remote POM" do
        let(:pom_body) { fixture("java", "poms", "remote_parent_pom.xml") }

        let(:struts_apps_maven_url) do
          "https://repo.maven.apache.org/maven2/"\
          "org/apache/struts/struts2-apps/2.5.10/struts2-apps-2.5.10.pom"
        end
        let(:struts_parent_maven_url) do
          "https://repo.maven.apache.org/maven2/"\
          "org/apache/struts/struts2-parent/2.5.10/struts2-parent-2.5.10.pom"
        end
        let(:struts_apps_maven_response) do
          fixture("java", "poms", "struts2-apps-2.5.10.pom")
        end
        let(:struts_parent_maven_response) do
          fixture("java", "poms", "struts2-parent-2.5.10.pom")
        end

        before do
          stub_request(:get, struts_apps_maven_url).
            to_return(status: 200, body: struts_apps_maven_response)
          stub_request(:get, struts_parent_maven_url).
            to_return(status: 200, body: struts_parent_maven_response)
        end

        let(:dependency_name) { "org.apache.logging.log4j:log4j-api" }
        let(:dependency_version) { "2.7" }
        let(:dependency_requirements) do
          [{ file: "pom.xml", requirement: "2.7", groups: [], source: nil }]
        end

        it { is_expected.to eq(false) }
      end
    end
  end
end
