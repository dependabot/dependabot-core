# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/file_updaters/java/maven/declaration_finder"

RSpec.describe Dependabot::FileUpdaters::Java::Maven::DeclarationFinder do
  let(:finder) do
    described_class.new(
      dependency_name: dependency_name,
      pom_content: pom_content
    )
  end

  let(:dependency_name) { "org.apache.httpcomponents:httpclient" }

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

      it "finds the declaration" do
        expect(declaration_node).to be_a(Nokogiri::XML::Node)
        expect(declaration_node.at_css("version").content).to eq("0.7.9")
        expect(declaration_node.at_css("artifactId").content).
          to eq("jacoco-maven-plugin")
        expect(declaration_node.at_css("groupId").content).to eq("org.jacoco")
      end
    end

    context "with a dependency in the pluginManagement node" do
      let(:pom_content) do
        fixture("java", "poms", "plugin_management_dependencies_pom.xml")
      end
      let(:dependency_name) { "org.jacoco:jacoco-maven-plugin" }

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
  end
end
