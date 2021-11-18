# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/maven/file_updater/declaration_finder"

RSpec.describe Dependabot::Maven::FileUpdater::DeclarationFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      declaring_requirement: declaring_requirement,
      dependency_files: dependency_files
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [declaring_requirement],
      package_manager: "maven"
    )
  end
  let(:dependency_name) { "org.apache.httpcomponents:httpclient" }
  let(:dependency_version) { "4.5.3" }
  let(:dependency_metadata) { { packaging_type: "jar" } }
  let(:declaring_requirement) do
    {
      requirement: dependency_version,
      file: "pom.xml",
      groups: groups,
      source: nil,
      metadata: dependency_metadata
    }
  end
  let(:dependency_files) { [pom] }
  let(:pom) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: fixture("poms", pom_fixture_name)
    )
  end
  let(:pom_fixture_name) { "basic_pom.xml" }
  let(:groups) { [] }

  describe "#declaration_nodes" do
    subject(:declaration_nodes) { finder.declaration_nodes }

    context "with a dependency in the dependencies node" do
      let(:pom_fixture_name) { "basic_pom.xml" }
      let(:groups) { ["test"] }

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("4.5.3")
        expect(declaration_node.at_css("artifactId").content).
          to eq("httpclient")
        expect(declaration_node.at_css("groupId").content).
          to eq("org.apache.httpcomponents")
      end

      context "that doesn't match this dependency's groups" do
        let(:groups) { [] }

        it { is_expected.to be_empty }
      end
    end

    context "with a dependency that has a classifier" do
      let(:dependency_name) { "io.mockk:mockk:sources" }
      let(:dependency_version) { "1.0.0" }

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("1.0.0")
        expect(declaration_node.at_css("artifactId").content).
          to eq("mockk")
        expect(declaration_node.at_css("classifier").content).
          to eq("sources")
        expect(declaration_node.at_css("groupId").content).
          to eq("io.mockk")
      end
    end

    context "with a dependency in the dependency management node" do
      let(:pom_fixture_name) { "dependency_management_pom.xml" }

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("4.5.3")
        expect(declaration_node.at_css("artifactId").content).
          to eq("httpclient")
        expect(declaration_node.at_css("groupId").content).
          to eq("org.apache.httpcomponents")
      end
    end

    context "with a dependency in the parent node" do
      let(:pom_fixture_name) { "pom_with_parent.xml" }
      let(:dependency_name) do
        "org.springframework.boot:spring-boot-starter-parent"
      end
      let(:dependency_version) { "1.5.9.RELEASE" }
      let(:dependency_metadata) { { packaging_type: "pom" } }

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).
          to eq("1.5.9.RELEASE")
        expect(declaration_node.at_css("artifactId").content).
          to eq("spring-boot-starter-parent")
        expect(declaration_node.at_css("groupId").content).
          to eq("org.springframework.boot")
      end
    end

    context "with a dependency in the plugins node" do
      let(:pom_fixture_name) { "plugin_dependencies_pom.xml" }
      let(:dependency_name) { "org.jacoco:jacoco-maven-plugin" }
      let(:dependency_version) { "0.7.9" }

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("0.7.9")
        expect(declaration_node.at_css("artifactId").content).
          to eq("jacoco-maven-plugin")
        expect(declaration_node.at_css("groupId").content).to eq("org.jacoco")
      end

      context "missing a groupId" do
        let(:pom_fixture_name) { "plugin_dependencies_missing_group_id.xml" }
        let(:dependency_name) do
          "org.apache.maven.plugins:spring-boot-maven-plugin"
        end
        let(:dependency_version) { "1.5.8.RELEASE" }

        it "finds the declaration" do
          expect(declaration_nodes.count).to eq(1)

          declaration_node = declaration_nodes.first
          expect(declaration_node).to be_a(Nokogiri::XML::Node)
          expect(declaration_node.at_css("version").content).
            to eq("1.5.8.RELEASE")
          expect(declaration_node.at_css("artifactId").content).
            to eq("spring-boot-maven-plugin")
          expect(declaration_node.at_css("groupId")).to be_nil
        end
      end
    end

    context "with a dependency in the extensions node" do
      let(:pom_fixture_name) { "extension_dependencies_pom.xml" }
      let(:dependency_name) { "org.jacoco:jacoco-maven-extension" }
      let(:dependency_version) { "0.7.9" }

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("0.7.9")
        expect(declaration_node.at_css("artifactId").content).
          to eq("jacoco-maven-extension")
        expect(declaration_node.at_css("groupId").content).to eq("org.jacoco")
      end
    end

    context "with a dependency in the pluginManagement node" do
      let(:pom_fixture_name) { "plugin_management_dependencies_pom.xml" }
      let(:dependency_name) { "org.jacoco:jacoco-maven-plugin" }
      let(:dependency_version) { "0.7.9" }

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("0.7.9")
        expect(declaration_node.at_css("artifactId").content).
          to eq("jacoco-maven-plugin")
        expect(declaration_node.at_css("groupId").content).to eq("org.jacoco")
      end
    end

    context "with a nested dependency" do
      let(:pom_fixture_name) { "nested_dependency_pom.xml" }
      let(:dependency_name) { "com.puppycrawl.tools:checkstyle" }
      let(:dependency_version) { "8.2" }
      let(:dependency_metadata) do
        { property_name: "checkstyle.version", packaging_type: "jar" }
      end

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).
          to eq("${checkstyle.version}")
        expect(declaration_node.at_css("artifactId").content).
          to eq("checkstyle")
        expect(declaration_node.at_css("groupId").content).
          to eq("com.puppycrawl.tools")
      end
    end

    context "with a plugin within a plugin" do
      let(:pom_fixture_name) { "plugin_within_plugin.xml" }
      let(:dependency_name) { "jp.skypencil.findbugs.slf4j:bug-pattern" }
      let(:dependency_version) { "1.4.0" }

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).
          to eq("1.4.0")
        expect(declaration_node.at_css("artifactId").content).
          to eq("bug-pattern")
        expect(declaration_node.at_css("groupId").content).
          to eq("jp.skypencil.findbugs.slf4j")
      end
    end

    context "with a repeated dependency" do
      let(:pom_fixture_name) { "repeated_pom_same_version.xml" }
      let(:dependency_name) { "org.apache.maven.plugins:maven-javadoc-plugin" }
      let(:dependency_version) { "2.10.4" }

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).
          to eq("2.10.4")
        expect(declaration_node.at_css("artifactId").content).
          to eq("maven-javadoc-plugin")
        expect(declaration_node.at_css("groupId").content).
          to eq("org.apache.maven.plugins")
      end

      context "where the versions are identical" do
        let(:pom_fixture_name) { "repeated_pom_identical.xml" }

        it "finds the declaration" do
          expect(declaration_nodes.count).to eq(2)

          expect(declaration_nodes.first.to_s).to include("dependency")
          expect(declaration_nodes.last.to_s).to include("plugin")

          expect(declaration_nodes.first).to be_a(Nokogiri::XML::Node)
          expect(declaration_nodes.first.at_css("version").content).
            to eq("2.10.4")
          expect(declaration_nodes.first.at_css("artifactId").content).
            to eq("maven-javadoc-plugin")
          expect(declaration_nodes.first.at_css("groupId").content).
            to eq("org.apache.maven.plugins")
        end

        context "but differ by distribution type" do
          let(:pom_fixture_name) { "repeated_pom_multiple_types.xml" }

          it "finds the declaration" do
            expect(declaration_nodes.count).to eq(1)

            expect(declaration_nodes.first).to be_a(Nokogiri::XML::Node)
            expect(declaration_nodes.first.at_css("type")).to be_nil
          end

          context "looking for the bespoke type" do
            let(:dependency_metadata) { { packaging_type: "test-jar" } }

            it "finds the declaration" do
              expect(declaration_nodes.count).to eq(1)

              expect(declaration_nodes.first).to be_a(Nokogiri::XML::Node)
              expect(declaration_nodes.first.at_css("type").content).
                to eq("test-jar")
            end
          end
        end
      end
    end

    context "with a groupId property" do
      let(:dependency_files) { [pom, child_pom] }
      let(:pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "sigtran.pom")
        )
      end
      let(:child_pom) do
        Dependabot::DependencyFile.new(
          name: "map/pom.xml",
          content: fixture("poms", "sigtran-map.pom")
        )
      end
      let(:dependency_name) { "uk.me.lwood.sigtran:sigtran-tcap" }
      let(:dependency_version) { "0.9-SNAPSHOT" }
      let(:declaring_requirement) do
        {
          requirement: dependency_version,
          file: "map/pom.xml",
          groups: [],
          source: nil,
          metadata: { property_name: "project.version", packaging_type: "jar" }
        }
      end

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).
          to eq("${project.version}")
        expect(declaration_node.at_css("artifactId").content).
          to eq("sigtran-tcap")
        expect(declaration_node.at_css("groupId").content).
          to eq("${project.groupId}")
      end

      context "that is missing for an unrelated dependency" do
        let(:dependency_files) { [pom] }
        let(:pom) do
          Dependabot::DependencyFile.new(
            name: "pom.xml",
            content: fixture("poms", "missing_property_group_id.xml")
          )
        end
        let(:dependency_name) { "io.reactivex.rxjava2:rxjava" }
        let(:dependency_version) { "2.1.6" }
        let(:declaring_requirement) do
          {
            requirement: dependency_version,
            file: "pom.xml",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }
        end

        it "finds the declaration" do
          expect(declaration_nodes.count).to eq(1)

          declaration_node = declaration_nodes.first
          expect(declaration_node).to be_a(Nokogiri::XML::Node)
          expect(declaration_node.at_css("version").content).to eq("2.1.6")
          expect(declaration_node.at_css("artifactId").content).to eq("rxjava")
          expect(declaration_node.at_css("groupId").content).
            to eq("io.reactivex.rxjava2")
        end
      end
    end

    context "with an inherited property" do
      let(:dependency_files) { [pom, child_pom, grandchild_pom] }
      let(:pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "multimodule_pom.xml")
        )
      end
      let(:child_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/pom.xml",
          content: fixture("poms", "legacy_pom.xml")
        )
      end
      let(:grandchild_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/some-spring-project/pom.xml",
          content: fixture("poms", "some_spring_project_pom.xml")
        )
      end
      let(:dependency_name) { "org.springframework:spring-aop" }
      let(:dependency_version) { "2.5.6" }
      let(:dependency_metadata) do
        { property_name: "spring.version", packaging_type: "jar" }
      end
      let(:declaring_requirement) do
        {
          requirement: dependency_version,
          file: "legacy/some-spring-project/pom.xml",
          groups: [],
          source: nil,
          metadata: dependency_metadata
        }
      end

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).
          to eq("${spring.version}")
        expect(declaration_node.at_css("artifactId").content).
          to eq("spring-aop")
        expect(declaration_node.at_css("groupId").content).
          to eq("org.springframework")
      end
    end

    context "with a plugin that contains a nested plugin configuration declaration" do
      let(:pom) do
        Dependabot::DependencyFile.new(name: "pom.xml", content: fixture("poms", "nested_plugin.xml"))
      end
      let(:dependency_name) { "org.jetbrains.kotlin:kotlin-maven-plugin" }
      let(:dependency_version) { "1.4.30" }
      let(:declaring_requirement) do
        {
          requirement: dependency_version,
          file: "pom.xml",
          groups: [],
          source: nil,
          metadata: { packaging_type: "jar", property_name: "kotlin.version" }
        }
      end

      it "finds the declaration" do
        expect(declaration_nodes.count).to eq(1)

        declaration_node = declaration_nodes.first
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_xpath("./*/version").content).to eq("${kotlin.version}")
        expect(declaration_node.at_xpath("./*/artifactId").content).to eq("kotlin-maven-plugin")
        expect(declaration_node.at_xpath("./*/groupId").content).to eq("org.jetbrains.kotlin")
      end
    end
  end
end
