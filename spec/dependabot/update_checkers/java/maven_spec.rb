# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/java/maven"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Java::Maven do
  it_behaves_like "an update checker"

  let(:maven_central_metadata_url) do
    "https://search.maven.org/remotecontent?filepath="\
    "com/google/guava/guava/maven-metadata.xml"
  end

  before do
    stub_request(:get, maven_central_metadata_url).
      to_return(
        status: 200,
        body: fixture("java", "maven_central_metadata.xml")
      )
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end
  let(:dependency_files) { [] }
  let(:credentials) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "maven"
    )
  end
  let(:dependency_requirements) do
    [{ file: "pom.xml", requirement: "23.3-jre", groups: [], source: nil }]
  end
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "23.3-jre" }

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(described_class::Version.new("23.6-jre")) }
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }
    it { is_expected.to eq(described_class::Version.new("23.6-jre")) }
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    before do
      allow(checker).
        to receive(:latest_version).
        and_return(described_class::Version.new("23.6-jre"))
    end

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: dependency_requirements,
          latest_version: "23.6-jre"
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [
            {
              file: "pom.xml",
              requirement: "23.6-jre",
              groups: [],
              source: nil
            }
          ]
        )
    end
  end
end
