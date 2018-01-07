# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/file_updaters/java/maven"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Java::Maven do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: [pom],
      dependencies: [dependency],
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end
  let(:pom) do
    Dependabot::DependencyFile.new(content: pom_body, name: "pom.xml")
  end
  let(:pom_body) { fixture("java", "poms", "basic_pom.xml") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "org.apache.httpcomponents:httpclient",
      version: "4.6.1",
      requirements: [
        {
          file: "pom.xml",
          requirement: "4.6.1",
          groups: [],
          source: nil
        }
      ],
      previous_requirements: [
        {
          file: "pom.xml",
          requirement: "4.5.3",
          groups: [],
          source: nil
        }
      ],
      package_manager: "maven"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated pom file" do
      subject(:updated_pom_file) do
        updated_files.find { |f| f.name == "pom.xml" }
      end

      its(:content) { is_expected.to include "<version>4.6.1</version>" }
      its(:content) { is_expected.to include "<version>23.3-jre</version>" }

      it "doesn't update the formatting of the POM" do
        expect(updated_pom_file.content).
          to include(%(<project xmlns="http://maven.apache.org/POM/4.0.0"\n))
      end

      context "when the requirement is a hard requirement" do
        let(:pom_body) { fixture("java", "poms", "hard_requirement_pom.xml") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.apache.httpcomponents:httpclient",
            version: "4.6.1",
            requirements: [
              {
                file: "pom.xml",
                requirement: "[4.6.1]",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "pom.xml",
                requirement: "[4.5.3]",
                groups: [],
                source: nil
              }
            ],
            package_manager: "maven"
          )
        end

        its(:content) { is_expected.to include "<version>[4.6.1]</version>" }
        its(:content) { is_expected.to include "<version>[23.3-jre]</version>" }
      end
    end
  end

  context "pom with dependency management" do
    let(:pom_body) { fixture("java", "poms", "dependency_management_pom.xml") }
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated pom file" do
      subject(:updated_pom_file) do
        updated_files.find { |f| f.name == "pom.xml" }
      end

      its(:content) { is_expected.to include "<dependencyManagement>" }
      its(:content) { is_expected.to include "<version>4.6.1</version>" }
      its(:content) { is_expected.to include "<version>23.3-jre</version>" }
    end
  end

  context "pom with plugins" do
    let(:pom_body) { fixture("java", "poms", "plugin_dependencies_pom.xml") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "org.jacoco:jacoco-maven-plugin",
        version: "0.8.0",
        requirements: [
          {
            file: "pom.xml",
            requirement: "0.8.0",
            groups: [],
            source: nil
          }
        ],
        previous_requirements: [
          {
            file: "pom.xml",
            requirement: "0.7.9",
            groups: [],
            source: nil
          }
        ],
        package_manager: "maven"
      )
    end

    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated pom file" do
      subject(:updated_pom_file) do
        updated_files.find { |f| f.name == "pom.xml" }
      end

      its(:content) { is_expected.to include "<plugins>" }
      its(:content) { is_expected.to include "<version>0.8.0</version>" }
      its(:content) do
        is_expected.to include "<version>1.5.8.RELEASE</version>"
      end
    end
  end

  context "pom with pluginManagement" do
    let(:pom_body) do
      fixture("java", "poms", "plugin_management_dependencies_pom.xml")
    end

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "org.jacoco:jacoco-maven-plugin",
        version: "0.8.0",
        requirements: [
          {
            file: "pom.xml",
            requirement: "0.8.0",
            groups: [],
            source: nil
          }
        ],
        previous_requirements: [
          {
            file: "pom.xml",
            requirement: "0.7.9",
            groups: [],
            source: nil
          }
        ],
        package_manager: "maven"
      )
    end

    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated pom file" do
      subject(:updated_pom_file) do
        updated_files.find { |f| f.name == "pom.xml" }
      end

      its(:content) { is_expected.to include "<pluginManagement>" }
      its(:content) { is_expected.to include "<version>0.8.0</version>" }
      its(:content) do
        is_expected.to include "<version>1.5.8.RELEASE</version>"
      end
    end
  end

  context "pom with dependency version defined by a property" do
    let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "org.springframework:spring-beans",
        version: "5.0.0.RELEASE",
        requirements: [
          {
            file: "pom.xml",
            requirement: "5.0.0.RELEASE",
            groups: [],
            source: nil
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
      )
    end

    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated pom file with correct property value" do
      subject(:updated_pom_file) do
        updated_files.find { |f| f.name == "pom.xml" }
      end

      it "updates the version in the POM" do
        expect(updated_pom_file.content).
          to include(
            "<springframework.version>5.0.0.RELEASE</springframework.version>"
          )
      end

      it "doesn't update the formatting of the POM" do
        expect(updated_pom_file.content).
          to include(%(<project xmlns="http://maven.apache.org/POM/4.0.0"\n))
      end
    end
  end
end
