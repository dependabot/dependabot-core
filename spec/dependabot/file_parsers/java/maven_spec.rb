# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/java/maven"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Java::Maven do
  it_behaves_like "a dependency file parser"

  let(:files) { [pom] }
  let(:pom) do
    Dependabot::DependencyFile.new(name: "pom.xml", content: pom_body)
  end
  let(:pom_body) { fixture("java", "poms", "basic_pom.xml") }
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
              metadata: nil
            }]
          )
        end
      end
    end

    context "with rogue whitespace" do
      let(:pom_body) { fixture("java", "poms", "whitespace.xml") }

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
              metadata: nil
            }]
          )
        end
      end
    end

    context "for dependencyManagement dependencies" do
      let(:pom_body) do
        fixture("java", "poms", "dependency_management_pom.xml")
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
              metadata: nil
            }]
          )
        end
      end
    end

    context "for plugin dependencies" do
      let(:pom_body) { fixture("java", "poms", "plugin_dependencies_pom.xml") }

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
              metadata: nil
            }]
          )
        end
      end

      context "missing a groupId" do
        let(:pom_body) do
          fixture("java", "poms", "plugin_dependencies_missing_group_id.xml")
        end

        its(:length) { is_expected.to eq(0) }
      end

      context "with a groupId buried in a configuration" do
        # This groupId doesn't belong to the plugin, and should not be used
        let(:pom_body) { fixture("java", "poms", "powerunit_pom.xml") }

        it "doesn't include the plugin" do
          expect(dependencies.map(&:name)).
            to_not include("${project.groupId}:maven-install-plugin")
        end
      end
    end

    context "for extension dependencies" do
      let(:pom_body) do
        fixture("java", "poms", "extension_dependencies_pom.xml")
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
              metadata: nil
            }]
          )
        end
      end
    end

    context "for pluginManagement dependencies" do
      let(:pom_body) do
        fixture("java", "poms", "plugin_management_dependencies_pom.xml")
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
              metadata: nil
            }]
          )
        end
      end
    end

    context "for versions defined by a property" do
      let(:pom_body) { fixture("java", "poms", "property_pom.xml") }

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
              metadata: { property_name: "springframework.version" }
            }]
          )
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies[1] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("org.springframework:spring-context")
          expect(dependency.version).to eq("4.3.12.RELEASE.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.3.12.RELEASE.1",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { property_name: "springframework.version" }
            }]
          )
        end
      end

      context "where the property is the project version" do
        let(:pom_body) { fixture("java", "poms", "project_version_pom.xml") }

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
                metadata: { property_name: "project.version" }
              }]
            )
          end
        end
      end

      context "when the property is missing" do
        let(:pom_body) { fixture("java", "poms", "missing_property.xml") }

        its(:length) { is_expected.to eq(2) }

        it "excludes the dependencies that use a missing property" do
          expect(dependencies.map(&:name)).
            to match_array(
              %w(org.apache.httpcomponents:httpclient com.google.guava:guava)
            )
        end

        context "and is required for all dependencies" do
          let(:pom_body) { fixture("java", "poms", "missing_property_all.xml") }

          it "raises a helpful error" do
            expect { parser.parse }.
              to raise_error(Dependabot::DependencyFileNotEvaluatable) do |err|
                expect(err.message).
                  to eq("Property not found: springframework.version")
              end
          end
        end
      end
    end

    context "for a version inherited from a parent pom" do
      let(:pom_body) { fixture("java", "poms", "pom_with_parent.xml") }

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
              metadata: nil
            }]
          )
        end
      end
    end

    context "for a groupId inherited from a parent pom" do
      let(:files) { [pom, child_pom] }
      let(:pom_body) { fixture("java", "poms", "sigtran.pom") }
      let(:child_pom) do
        Dependabot::DependencyFile.new(
          name: "sigtran-map/pom.xml",
          content: fixture("java", "poms", "sigtran-map.pom")
        )
      end

      it "fills in the property value correctly" do
        expect(dependencies.map(&:name)).
          to include("uk.me.lwood.sigtran:sigtran-tcap")
        expect(dependencies.map(&:name)).
          to include("junit:junit")
      end

      context "when the parent was downloaded only as a supporting POM" do
        let(:files) { [pom, parent_pom] }
        let(:pom_body) { fixture("java", "poms", "sigtran-map.pom") }
        let(:parent_pom) do
          Dependabot::DependencyFile.new(
            name: "../pom_parent.xml",
            content: fixture("java", "poms", "sigtran.pom")
          )
        end

        it "excludes parent dependencies" do
          expect(dependencies.map(&:name)).
            to include("uk.me.lwood.sigtran:sigtran-tcap")
          expect(dependencies.map(&:name)).
            to_not include("junit:junit")
        end
      end
    end

    context "for a version range" do
      let(:pom_body) { fixture("java", "poms", "range_pom.xml") }

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
              metadata: nil
            }]
          )
        end
      end
    end

    context "for a hard requirement" do
      let(:pom_body) { fixture("java", "poms", "hard_requirement_pom.xml") }

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
              metadata: nil
            }]
          )
        end
      end
    end

    context "for a versionless requirement" do
      let(:pom_body) { fixture("java", "poms", "versionless_pom.xml") }

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
              metadata: nil
            }]
          )
        end
      end
    end

    context "with a repeated dependency" do
      let(:pom_body) { fixture("java", "poms", "repeated_pom.xml") }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("org.apache.maven.plugins:maven-javadoc-plugin")
          expect(dependency.version).to eq("3.0.0-M1")
          expect(dependency.requirements).to eq(
            [
              {
                requirement: "3.0.0-M1",
                file: "pom.xml",
                groups: [],
                source: nil,
                metadata: { property_name: "maven-javadoc-plugin.version" }
              },
              {
                requirement: "2.10.4",
                file: "pom.xml",
                groups: [],
                source: nil,
                metadata: nil
              }
            ]
          )
        end
      end
    end

    context "for a dependency with compiler plugins" do
      let(:pom_body) { fixture("java", "poms", "compiler_plugins.xml") }

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
              metadata: nil
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

      it "gets the right dependencies" do
        expect(dependencies.map(&:name)).
          to match_array(
            %w(
              com.google.guava:guava
              junit:junit
              org.apache.struts:struts-core
              org.springframework:spring-aop
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
            [
              {
                requirement: "23.0-jre",
                file: "pom.xml",
                groups: [],
                source: nil,
                metadata: { property_name: "guava.version" }
              },
              {
                requirement: nil,
                file: "util/pom.xml",
                groups: [],
                source: nil,
                metadata: nil
              }
            ]
          )
        end
      end
    end
  end
end
