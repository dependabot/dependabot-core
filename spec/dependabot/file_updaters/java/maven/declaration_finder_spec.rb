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
    Dependabot::DependencyFile.new(name: "pom.xml", content: pom_content)
  end

  describe "#declaration_node" do
    subject(:declaration_node) { finder.declaration_node }

    context "with a dependency in the dependencies node" do
      let(:pom_content) { fixture("java", "poms", "basic_pom.xml") }

      it "finds the declaration" do
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("4.5.3")
        expect(declaration_node.at_css("artifactId").content).
          to eq("httpclient")
        expect(declaration_node.at_css("groupId").content).
          to eq("org.apache.httpcomponents")
      end
    end

    context "with a dependency in the dependency management node" do
      let(:pom_content) do
        fixture("java", "poms", "dependency_management_pom.xml")
      end

      it "finds the declaration" do
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("4.5.3")
        expect(declaration_node.at_css("artifactId").content).
          to eq("httpclient")
        expect(declaration_node.at_css("groupId").content).
          to eq("org.apache.httpcomponents")
      end
    end

    context "with a dependency in the parent node" do
      let(:pom_content) { fixture("java", "poms", "pom_with_parent.xml") }
      let(:dependency_name) do
        "org.springframework.boot:spring-boot-starter-parent"
      end
      let(:dependency_version) { "1.5.9.RELEASE" }

      it "finds the declaration" do
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
      let(:pom_content) do
        fixture("java", "poms", "plugin_dependencies_pom.xml")
      end
      let(:dependency_name) { "org.jacoco:jacoco-maven-plugin" }
      let(:dependency_version) { "0.7.9" }

      it "finds the declaration" do
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("0.7.9")
        expect(declaration_node.at_css("artifactId").content).
          to eq("jacoco-maven-plugin")
        expect(declaration_node.at_css("groupId").content).to eq("org.jacoco")
      end
    end

    context "with a dependency in the extensions node" do
      let(:pom_content) do
        fixture("java", "poms", "extension_dependencies_pom.xml")
      end
      let(:dependency_name) { "org.jacoco:jacoco-maven-extension" }
      let(:dependency_version) { "0.7.9" }

      it "finds the declaration" do
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("0.7.9")
        expect(declaration_node.at_css("artifactId").content).
          to eq("jacoco-maven-extension")
        expect(declaration_node.at_css("groupId").content).to eq("org.jacoco")
      end
    end

    context "with a dependency in the pluginManagement node" do
      let(:pom_content) do
        fixture("java", "poms", "plugin_management_dependencies_pom.xml")
      end
      let(:dependency_name) { "org.jacoco:jacoco-maven-plugin" }
      let(:dependency_version) { "0.7.9" }

      it "finds the declaration" do
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("0.7.9")
        expect(declaration_node.at_css("artifactId").content).
          to eq("jacoco-maven-plugin")
        expect(declaration_node.at_css("groupId").content).to eq("org.jacoco")
      end
    end

    context "with a nested dependency" do
      let(:pom_content) { fixture("java", "poms", "nested_dependency_pom.xml") }
      let(:dependency_name) { "com.puppycrawl.tools:checkstyle" }
      let(:dependency_version) { "8.2" }

      it "finds the declaration" do
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).
          to eq("${checkstyle.version}")
        expect(declaration_node.at_css("artifactId").content).
          to eq("checkstyle")
        expect(declaration_node.at_css("groupId").content).
          to eq("com.puppycrawl.tools")
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
          source: nil
        }
      end

      it "finds the declaration" do
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
