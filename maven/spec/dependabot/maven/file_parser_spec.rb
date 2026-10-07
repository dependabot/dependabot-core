# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/maven/file_parser"
require "dependabot/maven/file_parser/maven_dependency_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Maven::FileParser do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:pom_body) { fixture("poms", "basic_pom.xml") }
  let(:pom) do
    Dependabot::DependencyFile.new(name: "pom.xml", content: pom_body)
  end
  let(:files) { [pom] }

  it_behaves_like "a dependency file parser"

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "when dealing with top-level dependencies" do
      its(:length) { is_expected.to eq(3) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.guava:guava")
          expect(dependency.version).to eq("23.3-jre")
          expect(dependency.requirements).to eq(
            [{
              requirement: "23.3-jre",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies[1] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("org.apache.httpcomponents:httpclient")
          expect(dependency.version).to eq("4.5.3")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.5.3",
              file: "pom.xml",
              groups: ["test"],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end

      describe "the third dependency" do
        subject(:dependency) { dependencies[2] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("io.mockk:mockk")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.0",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: {
                classifier: "sources",
                packaging_type: "jar"
              }
            }]
          )
        end
      end
    end

    context "with extensions.xml" do
      let(:files) { [extensions, pom] }
      let(:extensions) do
        Dependabot::DependencyFile.new(name: ".mvn/extensions.xml", content: extensions_body)
      end
      let(:extensions_body) { fixture("extensions", "extensions.xml") }

      describe "the sole dependency" do
        subject(:dependency) { dependencies[3] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("io.takari.polyglot:polyglot-yaml")
          expect(dependency.version).to eq("0.4.6")
          expect(dependency.requirements).to eq(
            [{
              requirement: "0.4.6",
              file: ".mvn/extensions.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "with target-file" do
      let(:files) { [targetfile, pom] }
      let(:targetfile) do
        Dependabot::DependencyFile.new(name: "releng/myproject.target", content: targetfile_body)
      end
      let(:targetfile_body) { fixture("target-files", "example.target") }

      describe "the sole dependency" do
        subject(:dependency) { dependencies[3] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("commons-io:commons-io")
          expect(dependency.version).to eq("2.11.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.11.0",
              file: "releng/myproject.target",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "with rogue whitespace" do
      let(:pom_body) { fixture("poms", "whitespace.xml") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.guava:guava")
          expect(dependency.version).to eq("23.3-jre")
          expect(dependency.requirements).to eq(
            [{
              requirement: "23.3-jre",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing with dependencyManagement dependencies" do
      let(:pom_body) do
        fixture("poms", "dependency_management_pom.xml")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.guava:guava")
          expect(dependency.version).to eq("23.3-jre")
          expect(dependency.requirements).to eq(
            [{
              requirement: "23.3-jre",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing with plugin dependencies" do
      let(:pom_body) { fixture("poms", "plugin_dependencies_pom.xml") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.springframework.boot:spring-boot-maven-plugin")
          expect(dependency.version).to eq("1.5.8.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.5.8.RELEASE",
              file: "pom.xml",
              groups: ["plugin"],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end

      context "when dealing with missing a groupId" do
        let(:pom_body) do
          fixture("poms", "plugin_dependencies_missing_group_id.xml")
        end

        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name)
              .to eq("org.apache.maven.plugins:spring-boot-maven-plugin")
            expect(dependency.version).to eq("1.5.8.RELEASE")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.5.8.RELEASE",
                file: "pom.xml",
                groups: ["plugin"],
                source: nil,
                metadata: { packaging_type: "jar" }
              }]
            )
          end
        end
      end

      context "with a groupId buried in a configuration" do
        # This groupId doesn't belong to the plugin, and should not be used
        let(:pom_body) { fixture("poms", "powerunit_pom.xml") }

        it "doesn't include the plugin" do
          expect(dependencies.map(&:name))
            .not_to include("${project.groupId}:maven-install-plugin")
        end
      end
    end

    context "when dealing with plugin dependencies with artifactItems" do
      let(:pom_body) { fixture("poms", "plugin_dependencies_artifactItems_pom.xml") }

      its(:length) { is_expected.to eq(3) }

      describe "the first artifactItem dependency" do
        subject(:dependency) { dependencies[1] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("com.eclipsesource.minimal-json:minimal-json")
          expect(dependency.version).to eq("0.9.4")
          expect(dependency.requirements).to eq(
            [{
              requirement: "0.9.4",
              file: "pom.xml",
              groups: ["plugin"],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end

      describe "the second artifactItem dependency" do
        subject(:dependency) { dependencies[2] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.ow2.asm:asm")
          expect(dependency.version).to eq("9.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "9.1",
              file: "pom.xml",
              groups: ["plugin"],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing with extension dependencies" do
      let(:pom_body) do
        fixture("poms", "extension_dependencies_pom.xml")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.springframework.boot:spring-boot-maven-extension")
          expect(dependency.version).to eq("1.5.8.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.5.8.RELEASE",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing with annotationProcessorPaths dependencies" do
      let(:pom_body) do
        fixture("poms", "annotation_processor_paths_dependencies.xml")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.errorprone:error_prone_core")
          expect(dependency.version).to eq("2.9.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.9.0",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing with pluginManagement dependencies" do
      let(:pom_body) do
        fixture("poms", "plugin_management_dependencies_pom.xml")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.springframework.boot:spring-boot-maven-plugin")
          expect(dependency.version).to eq("1.5.8.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.5.8.RELEASE",
              file: "pom.xml",
              groups: ["plugin"],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing with versions defined by a property" do
      let(:pom_body) { fixture("poms", "property_pom.xml") }

      its(:length) { is_expected.to eq(4) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("org.springframework:spring-beans")
          expect(dependency.version).to eq("4.3.12.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.3.12.RELEASE",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: {
                property_name: "springframework.version",
                property_source: "pom.xml",
                packaging_type: "jar"
              }
            }]
          )
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies[1] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("org.springframework:spring-context")
          expect(dependency.version).to eq("4.3.12.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.3.12.RELEASE",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: {
                property_name: "springframework.version",
                property_source: "pom.xml",
                packaging_type: "jar"
              }
            }]
          )
        end
      end

      context "with multiple properties" do
        let(:pom_body) { fixture("poms", "property_pom_suffix.xml") }

        describe "the second dependency" do
          subject(:dependency) { dependencies[1] }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("org.springframework:spring-context")
            expect(dependency.version).to eq("4.3.12.RELEASE-context")
            expect(dependency.requirements).to eq(
              [{
                requirement: "4.3.12.RELEASE-context",
                file: "pom.xml",
                groups: [],
                source: nil,
                metadata: {
                  property_name: "springframework.version",
                  property_source: "pom.xml",
                  packaging_type: "jar"
                }
              }]
            )
          end
        end
      end

      context "when the property is the project version" do
        let(:pom_body) { fixture("poms", "project_version_pom.xml") }

        its(:length) { is_expected.to eq(3) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("org.springframework:spring-beans")
            expect(dependency.version).to eq("0.0.2-RELEASE")
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.0.2-RELEASE",
                file: "pom.xml",
                groups: [],
                source: nil,
                metadata: {
                  property_name: "project.version",
                  property_source: "pom.xml",
                  packaging_type: "jar"
                }
              }]
            )
          end
        end
      end

      context "when the property is missing" do
        let(:pom_body) { fixture("poms", "missing_property.xml") }

        its(:length) { is_expected.to eq(2) }

        it "excludes the dependencies that use a missing property" do
          expect(dependencies.map(&:name))
            .to match_array(
              %w(org.apache.httpcomponents:httpclient com.google.guava:guava)
            )
        end

        context "when the property is required for all dependencies" do
          let(:pom_body) { fixture("poms", "missing_property_all.xml") }

          it "raises a helpful error" do
            expect { parser.parse }
              .to raise_error(Dependabot::DependencyFileNotEvaluatable) do |err|
                expect(err.message)
                  .to eq("Property not found: springframework.version")
              end
          end
        end
      end

      context "when inheriting from a parent POM downloaded for support" do
        let(:files) { [pom, parent_pom] }
        let(:pom_body) { fixture("poms", "sigtran-map.pom") }
        let(:parent_pom) do
          Dependabot::DependencyFile.new(
            name: "../pom_parent.xml",
            content: fixture("poms", "sigtran.pom")
          )
        end

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("uk.me.lwood.sigtran:sigtran-tcap")
            expect(dependency.version).to eq("0.9-SNAPSHOT")
            expect(dependency.requirements).to eq(
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
            )
          end
        end
      end
    end

    context "when dealing with a version inherited from a parent pom" do
      let(:pom_body) { fixture("poms", "pom_with_parent.xml") }

      its(:length) { is_expected.to eq(8) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq(
            "org.springframework.boot:spring-boot-starter-parent"
          )
          expect(dependency.version).to eq("1.5.9.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.5.9.RELEASE",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "pom" }
            }]
          )
        end
      end
    end

    context "when dealing with a groupId inherited from a parent pom" do
      let(:files) { [pom, child_pom] }
      let(:pom_body) { fixture("poms", "sigtran.pom") }
      let(:child_pom) do
        Dependabot::DependencyFile.new(
          name: "sigtran-map/pom.xml",
          content: fixture("poms", "sigtran-map.pom")
        )
      end

      it "fills in the property value correctly" do
        expect(dependencies.map(&:name))
          .to include("uk.me.lwood.sigtran:sigtran-tcap")
        expect(dependencies.map(&:name))
          .to include("junit:junit")
      end

      context "when parent is named pom_parent" do
        let(:files) { [pom, parent_pom] }
        let(:pom_body) { fixture("poms", "sigtran-map.pom") }
        let(:parent_pom) do
          Dependabot::DependencyFile.new(
            name: "../pom_parent.xml",
            content: fixture("poms", "sigtran.pom")
          )
        end

        it "includes parent dependencies" do
          expect(dependencies.map(&:name))
            .to include("uk.me.lwood.sigtran:sigtran-tcap")
          expect(dependencies.map(&:name))
            .to include("junit:junit")
        end
      end
    end

    context "when dealing with a version range" do
      let(:pom_body) { fixture("poms", "range_pom.xml") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.guava:guava")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: "[23.3-jre,)",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing with a hard requirement" do
      let(:pom_body) { fixture("poms", "hard_requirement_pom.xml") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.guava:guava")
          expect(dependency.version).to eq("23.3-jre")
          expect(dependency.requirements).to eq(
            [{
              requirement: "[23.3-jre]",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing a versionless requirement" do
      let(:pom_body) { fixture("poms", "versionless_pom.xml") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.guava:guava")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: nil,
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing with an empty version requirement" do
      let(:pom_body) { fixture("poms", "empty_version_pom.xml") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.guava:guava")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: nil,
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "with a repeated dependency" do
      let(:pom_body) { fixture("poms", "repeated_pom.xml") }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.apache.maven.plugins:maven-javadoc-plugin")
          expect(dependency.version).to eq("2.10.4")
          expect(dependency.requirements).to eq(
            [{
              requirement: "3.0.0-M1",
              file: "pom.xml",
              groups: ["plugin"],
              source: nil,
              metadata: {
                property_name: "maven-javadoc-plugin.version",
                property_source: "pom.xml",
                packaging_type: "jar"
              }
            }, {
              requirement: "2.10.4",
              file: "pom.xml",
              groups: ["plugin"],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "when dealing with a dependency with compiler plugins" do
      let(:pom_body) { fixture("poms", "compiler_plugins.xml") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.guava:guava")
          expect(dependency.version).to eq("23.3-jre")
          expect(dependency.requirements).to eq(
            [{
              requirement: "23.3-jre",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "with a multimodule pom" do
      let(:files) do
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

      it "gets the right dependencies" do
        expect(dependencies.map(&:name))
          .to match_array(
            %w(
              com.google.guava:guava
              junit:junit
              org.apache.struts:struts-core
              org.springframework:spring-aop
              org.springframework:spring-testing
              org.apache.maven.plugins:maven-compiler-plugin
            )
          )
      end

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("com.google.guava:guava")
          expect(dependency.version).to eq("23.0-jre")
          expect(dependency.requirements).to eq(
            [{
              requirement: "23.0-jre",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: {
                property_name: "guava.version",
                property_source: "pom.xml",
                packaging_type: "jar"
              }
            }, {
              requirement: nil,
              file: "util/pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "with a multimodule custom named child poms" do
      let(:files) do
        [
          multimodule_custom_pom, submodule_one_pom, submodule_two_pom, submodule_three_pom
        ]
      end
      let(:multimodule_custom_pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "multimodule_custom_modules.xml")
        )
      end
      let(:submodule_one_pom) do
        Dependabot::DependencyFile.new(
          name: "submodule-one/pom.xml",
          content: fixture("poms", "multimodule_custom_modules_submodule_one_pom.xml")
        )
      end
      let(:submodule_two_pom) do
        Dependabot::DependencyFile.new(
          name: "submodule-two/notpom.xml",
          content: fixture("poms", "multimodule_custom_modules_submodule_two_pom.xml")
        )
      end
      let(:submodule_three_pom) do
        Dependabot::DependencyFile.new(
          name: "submodule-three/some-other-name.xml",
          content: fixture("poms", "multimodule_custom_modules_submodule_three_pom.xml")
        )
      end

      it "gets the right dependencies" do
        expect(dependencies.map(&:name))
          .to match_array(
            %w(
              net.sf.ehcache:ehcache
              org.apache.httpcomponents:httpclient
              org.springframework:spring-aop
              org.springframework:spring-core
            )
          )
      end

      describe "the standard pom dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.apache.httpcomponents:httpclient")
          expect(dependency.version).to eq("4.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.0",
              file: "submodule-one/pom.xml",
              groups: [],
              source: nil,
              metadata: {
                packaging_type: "jar"
              }
            }]
          )
        end
      end

      describe "the custom named pom dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.springframework:spring-core")
          expect(dependency.version).to eq("4.3.11.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.3.11.RELEASE",
              file: "submodule-three/some-other-name.xml",
              groups: [],
              source: nil,
              metadata: {
                packaging_type: "jar"
              }
            }]
          )
        end
      end
    end

    context "with an inheritance with custom parent name" do
      let(:files) do
        [
          pom, parentpom
        ]
      end
      let(:pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "inheritance_custom_named_pom.xml")
        )
      end
      let(:parentpom) do
        Dependabot::DependencyFile.new(
          name: "parentpom.xml",
          content: fixture("poms", "inheritance_custom_named_parent_pom.xml")
        )
      end

      it "gets the right dependencies" do
        expect(dependencies.map(&:name))
          .to match_array(
            %w(
              org.apache.httpcomponents:httpclient
              org.springframework:spring-aop
            )
          )
      end

      describe "the pom dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.apache.httpcomponents:httpclient")
          expect(dependency.version).to eq("4.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.0",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: {
                packaging_type: "jar"
              }
            }]
          )
        end
      end

      describe "the parent pom dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.springframework:spring-aop")
          expect(dependency.version).to eq("4.0.5.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.0.5.RELEASE",
              file: "parentpom.xml",
              groups: [],
              source: nil,
              metadata: {
                packaging_type: "jar"
              }
            }]
          )
        end
      end
    end

    context "with an inheritance and different types of parents" do
      let(:files) do
        [
          pom_with_existing_parent, parent_pom, pom_without_existing_parent
        ]
      end
      let(:pom_with_existing_parent) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "inheritance_custom_named_pom.xml")
        )
      end
      let(:parent_pom) do
        Dependabot::DependencyFile.new(
          name: "parent_pom.xml",
          content: fixture("poms", "inheritance_custom_named_parent_pom.xml")
        )
      end
      let(:pom_without_existing_parent) do
        Dependabot::DependencyFile.new(
          name: "pom_without_existing_parent.xml",
          content: fixture("poms", "inheritance_pom_no_parent_with_namespace_present.xml")
        )
      end

      it "gets the right dependencies including absent parent" do
        expect(dependencies.map(&:name))
          .to match_array(
            %w(
              net.sf.ehcache:ehcache
              org.apache.httpcomponents:httpclient
              org.example:maven-test-no-parent-artifact
              org.springframework:spring-aop
            )
          )
      end

      describe "the absent in repo parent dependency" do
        subject(:dependency) { dependencies[2] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name)
            .to eq("org.example:maven-test-no-parent-artifact")
          expect(dependency.version).to eq("1.0-SNAPSHOT")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0-SNAPSHOT",
              file: "pom_without_existing_parent.xml",
              groups: [],
              source: nil,
              metadata: {
                packaging_type: "pom"
              }
            }]
          )
        end
      end
    end

    context "with a native maven dependency tree parse" do
      before do
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new
        dependency_set << Dependabot::Dependency.new(
          name: "com.dependabot:basic-pom",
          version: "0.0.1-RELEASE",
          package_manager: "maven",
          requirements: [{
            requirement: "0.0.1-RELEASE",
            file: nil,
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              classifier: "",
              pom_file: "pom.xml"
            }
          }]
        )
        dependency_set << Dependabot::Dependency.new(
          name: "com.google.guava:guava",
          version: "23.3-jre",
          package_manager: "maven",
          requirements: [{
            requirement: "23.3-jre",
            file: nil,
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              classifier: "",
              pom_file: "pom.xml"
            }
          }]
        )
        dependency_set << Dependabot::Dependency.new(
          name: "org.apache.httpcomponents:httpclient",
          version: "4.5.3",
          package_manager: "maven",
          requirements: [{
            requirement: "4.5.3",
            file: nil,
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              classifier: "",
              pom_file: "pom.xml"
            }
          }]
        )
        dependency_set << Dependabot::Dependency.new(
          name: "io.mockk:mockk",
          version: "1.0.0",
          package_manager: "maven",
          requirements: [{
            requirement: "1.0.0",
            file: nil,
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              classifier: "",
              pom_file: "pom.xml"
            }
          }]
        )
        dependency_set << Dependabot::Dependency.new(
          name: "com.google.code.findbugs:jsr305",
          version: "1.3.9",
          package_manager: "maven",
          requirements: [{
            requirement: "1.3.9",
            file: nil,
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              classifier: "",
              pom_file: "pom.xml"
            }
          }]
        )
        dependency_set << Dependabot::Dependency.new(
          name: "org.apache.httpcomponents:httpcore",
          version: "4.4.6",
          package_manager: "maven",
          requirements: [{
            requirement: "4.4.6",
            file: nil,
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              classifier: "",
              pom_file: "pom.xml"
            }
          }]
        )

        allow(Dependabot::Maven::FileParser::MavenDependencyParser).to receive(:build_dependency_set)
          .and_return(dependency_set)
        allow(Dependabot::Experiments).to receive(:enabled?).and_return(false)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:maven_transitive_dependencies).and_return(true)
      end

      it "merges direct and transitive dependencies without the project itself" do
        expect(dependencies.map(&:name))
          .to match_array(
            %w(
              com.google.guava:guava
              org.apache.httpcomponents:httpclient
              io.mockk:mockk
              com.google.code.findbugs:jsr305
              org.apache.httpcomponents:httpcore
            )
          )
      end

      it "keeps the declared requirement and adds the scanned metadata" do
        dependency = dependencies.find { |dep| dep.name == "com.google.guava:guava" }

        expect(dependency.version).to eq("23.3-jre")
        expect(dependency.requirements).to eq(
          [{
            requirement: "23.3-jre",
            file: "pom.xml",
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              classifier: "",
              pom_file: "pom.xml"
            }
          }]
        )
      end

      it "keeps today's requirement shape for transitive dependencies" do
        dependency = dependencies.find { |dep| dep.name == "org.apache.httpcomponents:httpcore" }

        expect(dependency.version).to eq("4.4.6")
        expect(dependency.requirements).to eq(
          [{
            requirement: "4.4.6",
            file: nil,
            groups: [],
            source: nil,
            metadata: {
              packaging_type: "jar",
              classifier: "",
              pom_file: "pom.xml"
            }
          }]
        )
      end

      context "when the transitive experiment is off" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:maven_transitive_dependencies).and_return(false)
        end

        it "does not scan and returns only the declared dependencies" do
          expect(dependencies.map(&:name)).not_to include("org.apache.httpcomponents:httpcore")
          expect(dependencies.flat_map(&:requirements).map { |req| req[:file] }).to all(be_a(String))
          expect(Dependabot::Maven::FileParser::MavenDependencyParser).not_to have_received(:build_dependency_set)
        end
      end

      context "when the parser is asked to skip the dependency tree" do
        let(:parser) do
          described_class.new(dependency_files: files, source: source, options: { skip_dependency_tree: true })
        end

        it "does not scan and matches the flag-off result" do
          flag_off = described_class.new(dependency_files: files, source: source)
                                    .send(:parse_standard_dependencies)

          expect(dependencies).to eq(flag_off)
          expect(Dependabot::Maven::FileParser::MavenDependencyParser).not_to have_received(:build_dependency_set)
        end
      end
    end

    context "with the transitive experiment on" do
      let(:flag_off_dependencies) do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:maven_transitive_dependencies).and_return(false)
        described_class.new(dependency_files: files, source: source).parse
      end

      before do
        allow(Dependabot::Experiments).to receive(:enabled?).and_return(false)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:maven_transitive_dependencies).and_return(true)
      end

      context "when the scan fails" do
        let(:files) { [pom, targetfile] }
        let(:targetfile) do
          Dependabot::DependencyFile.new(
            name: "releng/myproject.target", content: fixture("target-files", "example.target")
          )
        end

        before do
          allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin).and_raise(
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "boom", error_context: {})
          )
        end

        it "returns the flag-off result" do
          expect(dependencies).to eq(flag_off_dependencies)
          expect(dependencies.map(&:name)).to include("commons-io:commons-io")
        end
      end

      context "with a .target file" do
        let(:files) { [pom, targetfile] }
        let(:targetfile) do
          Dependabot::DependencyFile.new(
            name: "releng/myproject.target", content: fixture("target-files", "example.target")
          )
        end

        before do
          allow(Dependabot::Maven::FileParser::MavenDependencyParser).to receive(:build_dependency_set)
            .and_return(Dependabot::FileParsers::Base::DependencySet.new)
        end

        it "keeps the .target dependencies" do
          dependency = dependencies.find { |dep| dep.name == "commons-io:commons-io" }

          expect(dependency.requirements.map(&:file)).to eq(["releng/myproject.target"])
        end
      end

      context "with a declared dependency whose version comes from a remote parent" do
        let(:pom_body) do
          <<~XML
            <project>
              <modelVersion>4.0.0</modelVersion>
              <parent>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-starter-parent</artifactId>
                <version>3.1.0</version>
                <relativePath/>
              </parent>
              <groupId>com.example</groupId>
              <artifactId>boot-app</artifactId>
              <version>1.0.0</version>
              <dependencies>
                <dependency>
                  <groupId>org.springframework.boot</groupId>
                  <artifactId>spring-boot-starter-web</artifactId>
                </dependency>
              </dependencies>
            </project>
          XML
        end

        before do
          allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin) do |output_file, **|
            File.write(
              output_file,
              {
                groupId: "com.example", artifactId: "boot-app", version: "1.0.0", type: "jar", scope: "",
                children: [{
                  groupId: "org.springframework.boot", artifactId: "spring-boot-starter-web", version: "3.1.0",
                  type: "jar", scope: "compile",
                  children: [{
                    groupId: "org.springframework", artifactId: "spring-web", version: "6.0.9",
                    type: "jar", scope: "compile"
                  }]
                }]
              }.to_json
            )
          end
        end

        it "uses the resolved version and keeps the nil requirement" do
          dependency = dependencies.find { |dep| dep.name == "org.springframework.boot:spring-boot-starter-web" }

          expect(dependency.version).to eq("3.1.0")
          expect(dependency.requirements.map { |req| [req[:requirement], req[:file]] }).to eq([[nil, "pom.xml"]])
          expect(dependency.requirements.first[:metadata]).to include(scope: "compile", pom_file: "pom.xml")
        end

        it "records what pulled a transitive dependency in" do
          dependency = dependencies.find { |dep| dep.name == "org.springframework:spring-web" }

          expect(dependency.requirements.first[:metadata][:pulled_in_by])
            .to eq("org.springframework.boot:spring-boot-starter-web")
        end
      end

      context "with a multi-module project" do
        let(:files) { [root_pom, api_pom, model_pom] }
        let(:root_pom) do
          Dependabot::DependencyFile.new(name: "pom.xml", content: <<~XML)
            <project>
              <modelVersion>4.0.0</modelVersion>
              <groupId>com.example</groupId>
              <artifactId>root</artifactId>
              <version>1.0</version>
              <packaging>pom</packaging>
              <modules><module>api</module><module>model</module></modules>
            </project>
          XML
        end
        let(:api_pom) do
          Dependabot::DependencyFile.new(name: "api/pom.xml", content: <<~XML)
            <project>
              <modelVersion>4.0.0</modelVersion>
              <parent><groupId>com.example</groupId><artifactId>root</artifactId><version>1.0</version></parent>
              <artifactId>api</artifactId>
              <dependencies>
                <dependency><groupId>com.example</groupId><artifactId>model</artifactId><version>1.0</version></dependency>
                <dependency>
                  <groupId>org.springframework.boot</groupId>
                  <artifactId>spring-boot-starter-tomcat</artifactId>
                  <version>1.2.6.RELEASE</version>
                </dependency>
              </dependencies>
            </project>
          XML
        end
        let(:model_pom) do
          Dependabot::DependencyFile.new(name: "model/pom.xml", content: <<~XML)
            <project>
              <modelVersion>4.0.0</modelVersion>
              <parent><groupId>com.example</groupId><artifactId>root</artifactId><version>1.0</version></parent>
              <artifactId>model</artifactId>
              <dependencies>
                <dependency><groupId>com.google.guava</groupId><artifactId>guava</artifactId><version>23.0</version></dependency>
              </dependencies>
            </project>
          XML
        end

        def node(name, version, children = [])
          group_id, artifact_id = name.split(":")
          { groupId: group_id, artifactId: artifact_id, version: version, type: "jar", scope: "compile",
            children: children }
        end

        before do
          allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin) do |output_file, **|
            guava = node("com.google.guava:guava", "23.0")
            tomcat_core = node("org.apache.tomcat.embed:tomcat-embed-core", "8.0.26")
            tomcat = node("org.springframework.boot:spring-boot-starter-tomcat", "1.2.6.RELEASE", [tomcat_core])
            model = node("com.example:model", "1.0", [guava])

            File.write(output_file, node("com.example:root", "1.0").to_json)
            File.write(File.join("model", output_file), model.to_json)
            File.write(File.join("api", output_file), node("com.example:api", "1.0", [model, tomcat]).to_json)
          end
        end

        it "finds transitive dependencies for each module without the modules themselves" do
          expect(dependencies.map(&:name)).to contain_exactly(
            "com.google.guava:guava",
            "org.springframework.boot:spring-boot-starter-tomcat",
            "org.apache.tomcat.embed:tomcat-embed-core"
          )

          tomcat = dependencies.find { |dep| dep.name == "org.apache.tomcat.embed:tomcat-embed-core" }
          expect(tomcat.requirements.map { |req| req[:metadata].slice(:pom_file, :pulled_in_by) }).to eq(
            [{ pom_file: "api/pom.xml", pulled_in_by: "org.springframework.boot:spring-boot-starter-tomcat" }]
          )

          guava = dependencies.find { |dep| dep.name == "com.google.guava:guava" }
          expect(guava.requirements.map { |req| [req[:file], req[:metadata][:pom_file]] }).to eq(
            [["model/pom.xml", "model/pom.xml"], [nil, "api/pom.xml"]]
          )
          expect(guava.requirements.last[:metadata][:pulled_in_by]).to eq("com.example:model")
        end
      end
    end

    context "with maven wrapper files" do
      let(:wrapper_content) { fixture("wrapper_files", "maven-wrapper-3.9.9-only-script.properties") }
      let(:wrapper_file) do
        Dependabot::DependencyFile.new(
          name: ".mvn/wrapper/maven-wrapper.properties",
          content: wrapper_content
        )
      end
      let(:files) { [pom, wrapper_file] }

      before do
        allow(Dependabot::Experiments).to receive(:enabled?).and_call_original
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:maven_wrapper_updater).and_return(true)
      end

      it "includes apache-maven as a dependency" do
        expect(dependencies.map(&:name)).to include("org.apache.maven:apache-maven")
      end

      it "includes maven-wrapper as a dependency" do
        expect(dependencies.map(&:name)).to include("org.apache.maven.wrapper:maven-wrapper")
      end

      it "sets the correct version for apache-maven" do
        dep = dependencies.find { |d| d.name == "org.apache.maven:apache-maven" }
        expect(dep.version).to eq("3.9.9")
      end

      it "sets the correct version for maven-wrapper" do
        dep = dependencies.find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep.version).to eq("3.3.4")
      end

      it "uses maven-distribution as the source type" do
        dep = dependencies.find { |d| d.name == "org.apache.maven:apache-maven" }
        expect(dep.requirements.first[:source][:type]).to eq("maven-distribution")
      end

      context "when transitive dependency parsing is enabled" do
        let(:wrapper_content) { fixture("wrapper_files", "maven-wrapper-3.9.6-bin.properties") }

        before do
          allow(Dependabot::Maven::FileParser::MavenDependencyParser).to receive(:build_dependency_set)
            .and_return(Dependabot::FileParsers::Base::DependencySet.new)
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:maven_transitive_dependencies).and_return(true)
        end

        it "includes the wrapper dependencies" do
          expect(dependencies.map(&:name)).to include(
            "org.apache.maven:apache-maven",
            "org.apache.maven.wrapper:maven-wrapper"
          )
        end

        it "preserves every wrapper requirement" do
          dependency = dependencies.find { |dep| dep.name == "org.apache.maven:apache-maven" }
          properties = dependency.requirements.map { |requirement| requirement.dig(:source, :property) }

          expect(properties).to contain_exactly("distributionUrl", "wrapperUrl")
        end
      end

      context "when the maven_wrapper_updater experiment is disabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:maven_wrapper_updater).and_return(false)
        end

        it "does not include apache-maven as a dependency" do
          expect(dependencies.map(&:name)).not_to include("org.apache.maven:apache-maven")
        end

        it "does not include maven-wrapper as a dependency" do
          expect(dependencies.map(&:name)).not_to include("org.apache.maven.wrapper:maven-wrapper")
        end
      end
    end

    describe "#ecosystem" do
      subject(:ecosystem) { parser.ecosystem }

      it "has the correct name" do
        expect(ecosystem.name).to eq "maven"
      end

      describe "#package_manager" do
        subject(:package_manager) { ecosystem.package_manager }

        it "returns the correct package manager" do
          expect(package_manager.name).to eq "maven"
          expect(package_manager.requirement).to be_nil
          expect(package_manager.version.to_s).to eq "NOT-AVAILABLE"
        end
      end

      describe "#language" do
        subject(:language) { ecosystem.language }

        it "returns the correct language" do
          expect(language.name).to eq "java"
          expect(language.requirement).to be_nil
          expect(language.version.to_s).to eq "NOT-AVAILABLE"
        end
      end
    end
  end
end
