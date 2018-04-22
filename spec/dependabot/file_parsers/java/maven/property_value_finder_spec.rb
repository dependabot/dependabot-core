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

  describe "#property_details" do
    subject(:property_details) do
      finder.property_details(
        property_name: property_name,
        callsite_pom: callsite_pom
      )
    end

    context "when the property is declared in the calling pom" do
      let(:base_pom_fixture_name) { "property_pom.xml" }
      let(:property_name) { "springframework.version" }
      let(:callsite_pom) { base_pom }
      its([:value]) { is_expected.to eq("4.3.12.RELEASE") }

      context "and the property is an attribute on the project" do
        let(:base_pom_fixture_name) { "project_version_pom.xml" }
        let(:property_name) { "project.version" }
        its([:value]) { is_expected.to eq("0.0.2-RELEASE") }
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
      its([:value]) { is_expected.to eq("2.5.6") }
    end

    context "when the property is declared in a remote pom" do
      let(:base_pom_fixture_name) { "remote_parent_pom.xml" }
      let(:property_name) { "log4j2.version" }
      let(:callsite_pom) { base_pom }

      let(:struts_apps_maven_url) do
        "https://repo.maven.apache.org/maven2/"\
        "org/apache/struts/struts2-apps/2.5.10/struts2-apps-2.5.10.pom"
      end
      let(:struts_parent_maven_url) do
        "https://repo.maven.apache.org/maven2/"\
        "org/apache/struts/struts2-parent/2.5.10/struts2-parent-2.5.10.pom"
      end
      let(:struts_apps_maven_response) do
        fixture("java", "poms", "struts2-apps-2.5.10.pom")
      end
      let(:struts_parent_maven_response) do
        fixture("java", "poms", "struts2-parent-2.5.10.pom")
      end

      before do
        stub_request(:get, struts_apps_maven_url).
          to_return(status: 200, body: struts_apps_maven_response)
        stub_request(:get, struts_parent_maven_url).
          to_return(status: 200, body: struts_parent_maven_response)
      end
      its([:value]) { is_expected.to eq("2.7") }
    end
  end
end
