# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/maven/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Maven::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [pom] }
  let(:pom) do
    Dependabot::DependencyFile.new(name: "pom.xml", content: pom_body)
  end
  let(:pom_body) { fixture("poms", "basic_pom.xml") }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "for top-level dependencies" do
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
          expect(dependency.name).to eq("io.mockk:mockk:sources")
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.0",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
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

    context "for dependencyManagement dependencies" do
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

    context "for plugin dependencies" do
      let(:pom_body) { fixture("poms", "plugin_dependencies_pom.xml") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("org.springframework.boot:spring-boot-maven-plugin")
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

      context "missing a groupId" do
        let(:pom_body) do
          fixture("poms", "plugin_dependencies_missing_group_id.xml")
        end

        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).
              to eq("org.apache.maven.plugins:spring-boot-maven-plugin")
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

      context "with a groupId buried in a configuration" do
        # This groupId doesn't belong to the plugin, and should not be used
        let(:pom_body) { fixture("poms", "powerunit_pom.xml") }

        it "doesn't include the plugin" do
          expect(dependencies.map(&:name)).
            to_not include("${project.groupId}:maven-install-plugin")
        end
      end
    end

    context "for extension dependencies" do
      let(:pom_body) do
        fixture("poms", "extension_dependencies_pom.xml")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("org.springframework.boot:spring-boot-maven-extension")
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

    context "for annotationProcessorPaths dependencies" do
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

    context "for pluginManagement dependencies" do
      let(:pom_body) do
        fixture("poms", "plugin_management_dependencies_pom.xml")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("org.springframework.boot:spring-boot-maven-plugin")
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

    context "for versions defined by a property" do
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

      context "where the property is the project version" do
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
          expect(dependencies.map(&:name)).
            to match_array(
              %w(org.apache.httpcomponents:httpclient com.google.guava:guava)
            )
        end

        context "and is required for all dependencies" do
          let(:pom_body) { fixture("poms", "missing_property_all.xml") }

          it "raises a helpful error" do
            expect { parser.parse }.
              to raise_error(Dependabot::DependencyFileNotEvaluatable) do |err|
                expect(err.message).
                  to eq("Property not found: springframework.version")
              end
          end
        end
      end

      context "that inherits from a parent POM downloaded for support" do
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

    context "for a version inherited from a parent pom" do
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

    context "for a groupId inherited from a parent pom" do
      let(:files) { [pom, child_pom] }
      let(:pom_body) { fixture("poms", "sigtran.pom") }
      let(:child_pom) do
        Dependabot::DependencyFile.new(
          name: "sigtran-map/pom.xml",
          content: fixture("poms", "sigtran-map.pom")
        )
      end

      it "fills in the property value correctly" do
        expect(dependencies.map(&:name)).
          to include("uk.me.lwood.sigtran:sigtran-tcap")
        expect(dependencies.map(&:name)).
          to include("junit:junit")
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
          expect(dependencies.map(&:name)).
            to include("uk.me.lwood.sigtran:sigtran-tcap")
          expect(dependencies.map(&:name)).
            to include("junit:junit")
        end
      end
    end

    context "for a version range" do
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

    context "for a hard requirement" do
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

    context "for a versionless requirement" do
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

    context "for an empty version requirement" do
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
          expect(dependency.name).
            to eq("org.apache.maven.plugins:maven-javadoc-plugin")
          expect(dependency.version).to eq("2.10.4")
          expect(dependency.requirements).to eq(
            [{
              requirement: "3.0.0-M1",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: {
                property_name: "maven-javadoc-plugin.version",
                property_source: "pom.xml",
                packaging_type: "jar"
              }
            }, {
              requirement: "2.10.4",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }]
          )
        end
      end
    end

    context "for a dependency with compiler plugins" do
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
        expect(dependencies.map(&:name)).
          to match_array(
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
          expect(dependency.name).
            to eq("com.google.guava:guava")
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
        expect(dependencies.map(&:name)).
          to match_array(
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
          expect(dependency.name).
            to eq("org.apache.httpcomponents:httpclient")
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
          expect(dependency.name).
            to eq("org.springframework:spring-core")
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
        expect(dependencies.map(&:name)).
          to match_array(
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
          expect(dependency.name).
            to eq("org.apache.httpcomponents:httpclient")
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
          expect(dependency.name).
            to eq("org.springframework:spring-aop")
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
        expect(dependencies.map(&:name)).
          to match_array(
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
          expect(dependency.name).
            to eq("org.example:maven-test-no-parent-artifact")
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
  end
end
