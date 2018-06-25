# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/java/maven/declaration_finder"

RSpec.describe Dependabot::FileUpdaters::Java::Maven::DeclarationFinder do
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
  let(:dependency_metadata) { nil }
  let(:declaring_requirement) do
    {
      requirement: dependency_version,
      file: "pom.xml",
      groups: [],
      source: nil,
      metadata: dependency_metadata
    }
  end
  let(:dependency_files) { [pom] }
  let(:pom) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: fixture("java", "poms", pom_fixture_name)
    )
  end
  let(:pom_fixture_name) { "basic_pom.xml" }

  describe "#declaration_nodes" do
    subject(:declaration_nodes) { finder.declaration_nodes }

    context "with a dependency in the dependencies node" do
      let(:pom_fixture_name) { "basic_pom.xml" }

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
      let(:dependency_metadata) { { property_name: "checkstyle.version" } }

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
      end
    end

    context "with a groupId property" do
      let(:dependency_files) { [pom, child_pom] }
      let(:pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("java", "poms", "sigtran.pom")
        )
      end
      let(:child_pom) do
        Dependabot::DependencyFile.new(
          name: "map/pom.xml",
          content: fixture("java", "poms", "sigtran-map.pom")
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
          metadata: { property_name: "project.version" }
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
    end

    context "with an inherited property" do
      let(:dependency_files) { [pom, child_pom, grandchild_pom] }
      let(:pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("java", "poms", "multimodule_pom.xml")
        )
      end
      let(:child_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/pom.xml",
          content: fixture("java", "poms", "legacy_pom.xml")
        )
      end
      let(:grandchild_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/some-spring-project/pom.xml",
          content: fixture("java", "poms", "some_spring_project_pom.xml")
        )
      end
      let(:dependency_name) { "org.springframework:spring-aop" }
      let(:dependency_version) { "2.5.6" }
      let(:dependency_metadata) { { property_name: "spring.version" } }
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
  end
end
