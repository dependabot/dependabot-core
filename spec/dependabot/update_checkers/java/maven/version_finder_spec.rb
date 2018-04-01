# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/java/maven/version_finder"

RSpec.describe Dependabot::UpdateCheckers::Java::Maven::VersionFinder do
  let(:finder) { described_class.new(dependency: dependency) }
  let(:version_class) { Dependabot::Utils::Java::Version }

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

  let(:maven_central_metadata_url) do
    "https://search.maven.org/remotecontent?filepath="\
    "com/google/guava/guava/maven-metadata.xml"
  end

  before do
    stub_request(:get, maven_central_metadata_url).
      to_return(
        status: 200,
        body: fixture("java", "maven_central_metadata", "with_release.xml")
      )
  end

  describe "#latest_release" do
    subject { finder.latest_release }
    it { is_expected.to eq(version_class.new("23.6-jre")) }

    context "when Maven Central doesn't return a release tag" do
      before do
        stub_request(:get, maven_central_metadata_url).
          to_return(
            status: 200,
            body: fixture("java", "maven_central_metadata", "no_release.xml")
          )
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#versions" do
    subject { finder.versions }
    its(:count) { is_expected.to eq(62) }
    its(:first) { is_expected.to eq(version_class.new("10.0-rc1")) }
    its(:last) { is_expected.to eq(version_class.new("23.6-jre")) }
  end
end
