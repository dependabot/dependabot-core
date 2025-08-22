# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/maven/update_checker/transitive_dependency_updater"

RSpec.describe Dependabot::Maven::UpdateChecker::TransitiveDependencyUpdater do
  let(:updater) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      target_version_details: target_version_details,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end

  let(:ignored_versions) { [] }
  let(:credentials) { [] }
  let(:version_class) { Dependabot::Maven::Version }
  let(:target_version_details) do
    {
      version: version_class.new("23.7-jre"),
      source_url: "https://repo.maven.apache.org/maven2"
    }
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "com.google.guava:guava",
      version: "23.6-jre",
      requirements: [
        {
          file: "pom.xml",
          requirement: "23.6-jre",
          groups: [],
          source: nil,
          metadata: { packaging_type: "jar" }
        }
      ],
      package_manager: "maven"
    )
  end

  let(:pom_body) do
    fixture("poms", "basic_pom.xml")
  end

  let(:dependency_files) do
    [Dependabot::DependencyFile.new(name: "pom.xml", content: pom_body)]
  end

  describe "#update_possible?" do
    subject(:update_possible) { updater.update_possible? }

    before do
      maven_central_metadata_url =
        "https://repo.maven.apache.org/maven2/" \
        "com/google/guava/guava/maven-metadata.xml"
      stub_request(:get, maven_central_metadata_url)
        .to_return(
          status: 200,
          body: fixture("maven_central_metadata", "with_release.xml")
        )
    end

    context "with no dependencies depending on the target" do
      it { is_expected.to be(true) }
    end

    context "with dependencies depending on the target" do
      # In the current implementation, this will return true since we use
      # a conservative approach and don't identify dependent packages yet
      it { is_expected.to be(true) }
    end
  end

  describe "#updated_dependencies" do
    subject(:updated_dependencies) { updater.updated_dependencies }

    before do
      maven_central_metadata_url =
        "https://repo.maven.apache.org/maven2/" \
        "com/google/guava/guava/maven-metadata.xml"
      stub_request(:get, maven_central_metadata_url)
        .to_return(
          status: 200,
          body: fixture("maven_central_metadata", "with_release.xml")
        )
    end

    it "updates the target dependency" do
      expect(updated_dependencies).to contain_exactly(
        an_object_having_attributes(
          name: "com.google.guava:guava",
          version: "23.7-jre",
          previous_version: "23.6-jre"
        )
      )
    end

    context "when update is not possible" do
      let(:target_version_details) { nil }

      it "raises an error" do
        expect { updated_dependencies }.to raise_error("Update not possible!")
      end
    end
  end
end