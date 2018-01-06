# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/java/maven"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Java::Maven do
  it_behaves_like "a dependency file parser"

  let(:files) { [pom] }
  let(:pom) do
    Dependabot::DependencyFile.new(name: "pom.xml", content: pom_body)
  end
  let(:pom_body) { fixture("java", "poms", "basic_pom.xml") }
  let(:parser) { described_class.new(dependency_files: files, repo: "org/nm") }

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
            [
              {
                requirement: "23.3-jre",
                file: "pom.xml",
                groups: [],
                source: nil
              }
            ]
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
            [
              {
                requirement: "23.3-jre",
                file: "pom.xml",
                groups: [],
                source: nil
              }
            ]
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
            [
              {
                requirement: "1.5.8.RELEASE",
                file: "pom.xml",
                groups: [],
                source: nil
              }
            ]
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
            [
              {
                requirement: "1.5.8.RELEASE",
                file: "pom.xml",
                groups: [],
                source: nil
              }
            ]
          )
        end
      end
    end

    context "for versions defined by a property" do
      let(:pom_body) { fixture("java", "poms", "property_pom.xml") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("org.springframework:spring-beans")
          expect(dependency.version).to eq("4.3.12.RELEASE")
          expect(dependency.requirements).to eq(
            [
              {
                requirement: "4.3.12.RELEASE",
                file: "pom.xml",
                groups: [],
                source: nil
              }
            ]
          )
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
            [
              {
                requirement: "[23.3-jre,)",
                file: "pom.xml",
                groups: [],
                source: nil
              }
            ]
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
            [
              {
                requirement: "[23.3-jre]",
                file: "pom.xml",
                groups: [],
                source: nil
              }
            ]
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
            [
              {
                requirement: nil,
                file: "pom.xml",
                groups: [],
                source: nil
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
            [
              {
                requirement: "23.3-jre",
                file: "pom.xml",
                groups: [],
                source: nil
              }
            ]
          )
        end
      end
    end
  end
end
