# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/maven/update_checker"
require "dependabot/maven/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Maven::UpdateChecker do
  let(:pom_body) { fixture("poms", "basic_pom.xml") }
  let(:pom) do
    Dependabot::DependencyFile.new(name: "pom.xml", content: pom_body)
  end
  let(:maven_central_version_files_url) do
    "https://repo.maven.apache.org/maven2/" \
      "com/google/guava/guava/23.6-jre/guava-23.6-jre.jar"
  end
  let(:maven_central_releases) do
    fixture("maven_central_metadata", "with_release.xml")
  end
  let(:version_class) { Dependabot::Maven::Version }
  let(:maven_central_metadata_url) do
    "https://repo.maven.apache.org/maven2/" \
      "com/google/guava/guava/maven-metadata.xml"
  end
  let(:security_advisories) { [] }
  let(:ignored_versions) { [] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_files) { [pom] }
  let(:dependency_version) { "23.3-jre" }
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_requirements) do
    [{
      file: "pom.xml",
      requirement: "23.3-jre",
      groups: [],
      metadata: { packaging_type: "jar" },
      source: nil
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "maven"
    )
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

  before do
    stub_request(:get, maven_central_metadata_url)
      .to_return(status: 200, body: maven_central_releases)
    stub_request(:head, maven_central_version_files_url)
      .to_return(status: 200)
  end

  it_behaves_like "an update checker"

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
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "com/google/guava/guava/23.7-rc1-android/guava-23.7-rc1-android.jar"
      end
      let(:maven_central_version_files) do
        fixture("maven_central_version_files", "guava-23.7.html")
      end

      it { is_expected.to eq(version_class.new("23.7-rc1-android")) }
    end

    context "when there are date-based versions" do
      let(:maven_central_releases) do
        fixture("maven_central_metadata", "with_date_releases.xml")
      end
      let(:dependency_name) { "commons-collections:commons-collections" }
      let(:dependency_version) { "3.1" }
      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/" \
          "commons-collections/commons-collections/maven-metadata.xml"
      end
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "commons-collections/commons-collections/3.2.2/" \
          "commons-collections-3.2.2.jar"
      end
      let(:maven_central_version_files) do
        fixture(
          "maven_central_version_files",
          "commons-collections-3.2.2.html"
        )
      end

      it { is_expected.to eq(version_class.new("3.2.2")) }

      context "when that's what we're using" do
        let(:dependency_version) { "20030418" }
        let(:maven_central_version_files_url) do
          "https://repo.maven.apache.org/maven2/" \
            "commons-collections/commons-collections/20040616/" \
            "commons-collections-20040616.jar"
        end
        let(:maven_central_version_files) do
          fixture(
            "maven_central_version_files",
            "commons-collections-20040616.html"
          )
        end

        it { is_expected.to eq(version_class.new("20040616")) }
      end
    end

    context "when the current version isn't normal" do
      let(:dependency_version) { "RELEASE802" }
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "com/google/guava/guava/23.0/guava-23.0.jar"
      end
      let(:maven_central_version_files) do
        fixture("maven_central_version_files", "guava-23.0.html")
      end

      it { is_expected.to eq(version_class.new("23.0")) }
    end

    context "when the version comes from a property" do
      let(:pom_body) { fixture("poms", "property_pom_single.xml") }
      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-beans/23.0/spring-beans-23.0.jar"
      end
      let(:maven_central_version_files) do
        fixture("maven_central_version_files", "spring-beans-23.0.html")
      end
      let(:dependency_requirements) do
        [{
          file: "pom.xml",
          requirement: "4.3.12.RELEASE",
          groups: [],
          metadata: { packaging_type: "jar" },
          source: nil
        }]
      end
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:dependency_version) { "4.3.12.RELEASE" }

      it { is_expected.to eq(version_class.new("23.0")) }

      context "when the property affects multiple dependencies" do
        let(:pom_body) { fixture("poms", "property_pom.xml") }

        it { is_expected.to eq(version_class.new("23.0")) }
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lsfv) { checker.lowest_security_fix_version }

    before do
      version_files_url = "https://repo.maven.apache.org/maven2/com/google/" \
                          "guava/guava/23.4-jre/guava-23.4-jre.jar"
      stub_request(:head, version_files_url)
        .to_return(status: 200)
    end

    it "finds the lowest available version" do
      expect(lsfv).to eq(version_class.new("23.4-jre"))
    end

    context "with a security vulnerability" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "maven",
            vulnerable_versions: ["< 23.5.0"]
          )
        ]
      end

      before do
        version_files_url = "https://repo.maven.apache.org/maven2/com/google/" \
                            "guava/guava/23.5-jre/guava-23.5-jre.jar"
        stub_request(:head, version_files_url)
          .to_return(status: 200)
      end

      it "finds the lowest available non-vulnerable version" do
        expect(lsfv).to eq(version_class.new("23.5-jre"))
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lrsfv) { checker.lowest_resolvable_security_fix_version }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "maven",
          vulnerable_versions: ["< 23.5.0"]
        )
      ]
    end

    before do
      version_files_url = "https://repo.maven.apache.org/maven2/com/google/" \
                          "guava/guava/23.5-jre/guava-23.5-jre.jar"
      stub_request(:head, version_files_url)
        .to_return(status: 200)
    end

    it "finds the lowest available non-vulnerable version" do
      expect(lrsfv).to eq(version_class.new("23.5-jre"))
    end

    context "with version from multi-dependency property" do
      before { allow(checker).to receive(:version_comes_from_multi_dependency_property?).and_return(true) }

      it "finds the lowest available non-vulnerable version" do
        expect(lrsfv).to eq(version_class.new("23.5-jre"))
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    it { is_expected.to eq(version_class.new("23.6-jre")) }

    context "when the version comes from a property" do
      let(:pom_body) { fixture("poms", "property_pom_single.xml") }
      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-beans/23.0/spring-beans-23.0.jar"
      end
      let(:maven_central_version_files) do
        fixture("maven_central_version_files", "spring-beans-23.0.html")
      end
      let(:dependency_requirements) do
        [{
          file: "pom.xml",
          requirement: "4.3.12.RELEASE",
          groups: [],
          source: nil,
          metadata: metadata
        }]
      end
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:dependency_version) { "4.3.12.RELEASE" }
      let(:metadata) do
        {
          property_name: "springframework.version",
          property_source: "pom.xml",
          packaging_type: "jar"
        }
      end

      it { is_expected.to eq(version_class.new("23.0")) }

      context "when the same property is also declared in another file" do
        let(:dependency_files) { [pom, other_pom] }
        let(:other_pom) do
          Dependabot::DependencyFile.new(
            name: "other/pom.xml",
            content: fixture("poms", "property_pom_other.xml")
          )
        end

        it { is_expected.to eq(version_class.new("23.0")) }
      end

      context "when the property affects multiple dependencies" do
        let(:pom_body) { fixture("poms", "property_pom.xml") }

        it { is_expected.to be_nil }
      end

      context "when dealing with a repeated dependency" do
        let(:pom_body) { fixture("poms", "repeated_pom.xml") }
        let(:maven_central_metadata_url) do
          "https://repo.maven.apache.org/maven2/" \
            "org/apache/maven/plugins/maven-javadoc-plugin/maven-metadata.xml"
        end
        let(:maven_central_version_files_url) do
          "https://repo.maven.apache.org/maven2/" \
            "org/apache/maven/plugins/maven-javadoc-plugin/23.0/" \
            "maven-javadoc-plugin-23.0.jar"
        end
        let(:maven_central_version_files) do
          fixture(
            "maven_central_version_files",
            "maven-javadoc-plugin-23.0.html"
          )
        end
        let(:dependency_name) do
          "org.apache.maven.plugins:maven-javadoc-plugin"
        end
        let(:dependency_requirements) do
          [{
            file: "pom.xml",
            requirement: "3.0.0-M1",
            groups: [],
            source: nil,
            metadata: metadata
          }, {
            file: "pom.xml",
            requirement: "2.10.4",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to eq(version_class.new("23.0")) }

        context "when the property affects multiple dependencies" do
          let(:pom_body) do
            fixture("poms", "repeated_multi_property_pom.xml")
          end
          let(:metadata) do
            {
              property_name: "maven-plugins.version",
              property_source: "pom.xml"
            }
          end

          it { is_expected.to be_nil }
        end

        context "with a nil requirement" do
          let(:dependency_requirements) do
            [{
              file: "pom.xml",
              requirement: "3.0.0-M1",
              groups: [],
              metadata: { packaging_type: "jar" },
              source: nil
            }, {
              file: "pom.xml",
              requirement: nil,
              groups: [],
              metadata: { packaging_type: "jar" },
              source: nil
            }]
          end

          it { is_expected.to eq(version_class.new("23.0")) }
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
          content: fixture("poms", "multimodule_pom.xml")
        )
      end
      let(:util_pom) do
        Dependabot::DependencyFile.new(
          name: "util/pom.xml",
          content: fixture("poms", "util_pom.xml")
        )
      end
      let(:business_app_pom) do
        Dependabot::DependencyFile.new(
          name: "business-app/pom.xml",
          content: fixture("poms", "business_app_pom.xml")
        )
      end
      let(:legacy_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/pom.xml",
          content: fixture("poms", "legacy_pom.xml")
        )
      end
      let(:webapp_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/webapp/pom.xml",
          content: fixture("poms", "webapp_pom.xml")
        )
      end
      let(:some_spring_project_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/some-spring-project/pom.xml",
          content: fixture("poms", "some_spring_project_pom.xml")
        )
      end

      context "when dealing with a dependency inherited by others" do
        let(:dependency_requirements) do
          [{
            requirement: "23.0-jre",
            file: "pom.xml",
            groups: [],
            metadata: { packaging_type: "jar" },
            source: nil
          }, {
            requirement: nil,
            file: "util/pom.xml",
            groups: [],
            metadata: { packaging_type: "jar" },
            source: nil
          }]
        end
        let(:dependency_name) { "com.google.guava:guava" }
        let(:dependency_version) { "23.0-jre" }

        it { is_expected.to eq(version_class.new("23.6-jre")) }
      end

      context "when dealing with a dependency that uses a property from its parent" do
        let(:dependency_requirements) do
          [{
            requirement: "2.5.6",
            file: "legacy/some-spring-project/pom.xml",
            groups: [],
            metadata: { packaging_type: "jar" },
            source: nil
          }]
        end
        let(:dependency_name) { "org.springframework:spring-aop" }
        let(:dependency_version) { "2.5.6" }
        let(:maven_central_metadata_url) do
          "https://repo.maven.apache.org/maven2/" \
            "org/springframework/spring-aop/maven-metadata.xml"
        end
        let(:maven_central_version_files_url) do
          "https://repo.maven.apache.org/maven2/" \
            "org/springframework/spring-aop/23.0/spring-aop-23.0.jar"
        end
        let(:maven_central_version_files) do
          fixture(
            "maven_central_version_files",
            "spring-aop-23.0.html"
          )
        end

        it { is_expected.to eq(version_class.new("23.0")) }
      end
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
            package_manager: "maven",
            safe_versions: ["> 19.0"]
          )
        ]
      end
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "com/google/guava/guava/20.0/guava-20.0.jar"
      end
      let(:maven_central_version_files) do
        fixture("maven_central_version_files", "guava-23.6.html")
          .gsub("23.6-jre", "20.0")
      end

      it { is_expected.to eq(version_class.new("20.0")) }
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater)
        .to receive(:new)
        .with(
          requirements: dependency_requirements,
          latest_version: "23.6-jre",
          source_url: "https://repo.maven.apache.org/maven2",
          properties_to_update: []
        )
        .and_call_original
      expect(checker.updated_requirements)
        .to eq(
          [{
            file: "pom.xml",
            requirement: "23.6-jre",
            groups: [],
            metadata: { packaging_type: "jar" },
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
            package_manager: "maven",
            safe_versions: ["> 19.0"]
          )
        ]
      end
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "com/google/guava/guava/20.0/guava-20.0.jar"
      end
      let(:maven_central_version_files) do
        fixture("maven_central_version_files", "guava-23.6.html")
          .gsub("23.6-jre", "20.0")
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater)
          .to receive(:new)
          .with(
            requirements: dependency_requirements,
            latest_version: "20.0",
            source_url: "https://repo.maven.apache.org/maven2",
            properties_to_update: []
          )
          .and_call_original
        expect(checker.updated_requirements)
          .to eq(
            [{
              file: "pom.xml",
              requirement: "20.0",
              groups: [],
              metadata: { packaging_type: "jar" },
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
    subject(:latest_version_resolvable_with_full_unlock) { checker.send(:latest_version_resolvable_with_full_unlock?) }

    context "with no latest version" do
      before { allow(checker).to receive(:latest_version).and_return(nil) }

      it { is_expected.to be_falsey }
    end

    context "with a non-property pom" do
      let(:pom_body) { fixture("poms", "basic_pom.xml") }

      it { is_expected.to be_falsey }
    end

    context "with a property pom" do
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:pom_body) { fixture("poms", "property_pom.xml") }
      let(:maven_central_metadata_url_beans) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_context) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-context/maven-metadata.xml"
      end
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-beans/23.6-jre/spring-beans-23.6-jre.jar"
      end
      let(:maven_central_version_files) do
        fixture("maven_central_version_files", "spring-beans-23.6.html")
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

      before do
        allow(checker)
          .to receive(:latest_version)
          .and_return(version_class.new("23.6-jre"))
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

      it "delegates to the PropertyUpdater" do
        expect(described_class::PropertyUpdater)
          .to receive(:new)
          .with(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: [],
            target_version_details: {
              version: version_class.new("23.6-jre"),
              source_url: "https://repo.maven.apache.org/maven2"
            }
          )
          .and_call_original
        expect(latest_version_resolvable_with_full_unlock).to be(true)
      end
    end
  end

  describe "#updated_dependencies_after_full_unlock" do
    subject(:checker_updated_dependencies_after_full_unlock) { checker.send(:updated_dependencies_after_full_unlock) }

    context "with a property pom" do
      let(:dependency_name) { "org.springframework:spring-beans" }
      let(:pom_body) { fixture("poms", "property_pom.xml") }
      let(:maven_central_metadata_url_beans) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-beans/maven-metadata.xml"
      end
      let(:maven_central_metadata_url_context) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-context/maven-metadata.xml"
      end
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/springframework/spring-beans/23.6-jre/spring-beans-23.6-jre.jar"
      end
      let(:maven_central_version_files) do
        fixture("maven_central_version_files", "spring-beans-23.6.html")
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

      before do
        allow(checker)
          .to receive(:latest_version)
          .and_return(version_class.new("23.6-jre"))
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

      it "delegates to the PropertyUpdater" do
        expect(described_class::PropertyUpdater)
          .to receive(:new)
          .with(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: [],
            target_version_details: {
              version: version_class.new("23.6-jre"),
              source_url: "https://repo.maven.apache.org/maven2"
            }
          )
          .and_call_original
        expect(checker_updated_dependencies_after_full_unlock).to eq(
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
    end
  end

  describe "#up_to_date?" do
    subject { checker.up_to_date? }

    context "when the current version isn't normal" do
      let(:dependency_version) { "RELEASE&802" }

      it { is_expected.to be(false) }
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :all) }

    context "when the current version isn't normal" do
      let(:dependency_version) { "RELEASE&802" }

      it { is_expected.to be(false) }
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    context "with a basic POM" do
      let(:pom_body) { fixture("poms", "basic_pom.xml") }

      it { is_expected.to be(true) }
    end

    context "with a property POM" do
      let(:pom_body) { fixture("poms", "property_pom.xml") }
      let(:dependency_name) { "org.springframework:spring-context" }
      let(:dependency_version) { "4.3.12.RELEASE.1" }
      let(:dependency_requirements) do
        [{
          file: "pom.xml",
          requirement: "4.3.12.RELEASE.1",
          groups: [],
          source: nil,
          metadata: {
            property_name: "springframework.version",
            property_source: "pom.xml"
          }
        }]
      end

      it { is_expected.to be(true) }

      context "when inheriting from a parent POM" do
        let(:dependency_files) { [pom, parent_pom] }
        let(:pom_body) { fixture("poms", "sigtran-map.pom") }
        let(:parent_pom) do
          Dependabot::DependencyFile.new(
            name: "../pom_parent.xml",
            content: fixture("poms", "sigtran.pom")
          )
        end
        let(:dependency_name) { "uk.me.lwood.sigtran:sigtran-tcap" }
        let(:dependency_version) { "0.9-SNAPSHOT" }
        let(:dependency_requirements) do
          [{
            file: "pom.xml",
            requirement: "0.9-SNAPSHOT",
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              property_name: "project.version",
              property_source: "../pom_parent.xml"
            }
          }]
        end

        it { is_expected.to be(true) }
      end

      context "when inheriting from a remote POM" do
        let(:pom_body) { fixture("poms", "remote_parent_pom.xml") }
        let(:dependency_name) { "org.apache.logging.log4j:log4j-api" }
        let(:dependency_version) { "2.7" }
        let(:dependency_requirements) do
          [{
            file: "pom.xml",
            requirement: "2.7",
            groups: [],
            source: nil,
            metadata: { property_name: "log4j2.version" }
          }]
        end

        let(:struts_apps_maven_url) do
          "https://repo.maven.apache.org/maven2/" \
            "org/apache/struts/struts2-apps/2.5.10/struts2-apps-2.5.10.pom"
        end
        let(:struts_parent_maven_url) do
          "https://repo.maven.apache.org/maven2/" \
            "org/apache/struts/struts2-parent/2.5.10/struts2-parent-2.5.10.pom"
        end
        let(:struts_apps_maven_response) do
          fixture("poms", "struts2-apps-2.5.10.pom")
        end
        let(:struts_parent_maven_response) do
          fixture("poms", "struts2-parent-2.5.10.pom")
        end

        before do
          stub_request(:get, struts_apps_maven_url)
            .to_return(status: 200, body: struts_apps_maven_response)
          stub_request(:get, struts_parent_maven_url)
            .to_return(status: 200, body: struts_parent_maven_response)
        end

        it { is_expected.to be(false) }
      end
    end
  end
end
