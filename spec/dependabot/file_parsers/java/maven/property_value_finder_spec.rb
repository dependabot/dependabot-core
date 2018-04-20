# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/java/maven/property_value_finder"

RSpec.describe Dependabot::FileParsers::Java::Maven::PropertyValueFinder do
  let(:finder) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [base_pom] }
  let(:base_pom) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: fixture("java", "poms", base_pom_fixture_name)
    )
  end
  let(:base_pom_fixture_name) { "property_pom.xml" }

  describe "#property_value" do
    subject(:property_value) do
      finder.property_value(
        property_name: property_name,
        callsite_pom: callsite_pom
      )
    end

    context "when the property is declared in the calling pom" do
      let(:base_pom_fixture_name) { "property_pom.xml" }
      let(:property_name) { "springframework.version" }
      let(:callsite_pom) { base_pom }
      it { is_expected.to eq("4.3.12.RELEASE") }

      context "and the property is an attribute on the project" do
        let(:base_pom_fixture_name) { "project_version_pom.xml" }
        let(:property_name) { "project.version" }
        it { is_expected.to eq("0.0.2-RELEASE") }
      end
    end

    context "when the property is declared in a parent pom" do
      let(:dependency_files) { [base_pom, child_pom, grandchild_pom] }
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

      let(:base_pom_fixture_name) { "multimodule_pom.xml" }
      let(:property_name) { "spring.version" }
      let(:callsite_pom) { grandchild_pom }
      it { is_expected.to eq("2.5.6") }
    end
  end
end
