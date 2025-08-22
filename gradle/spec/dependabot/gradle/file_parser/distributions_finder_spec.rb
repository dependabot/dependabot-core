# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/file_parser/distributions_finder"

RSpec.describe Dependabot::Gradle::FileParser::DistributionsFinder do
  describe ".resolve_dependency" do
    shared_examples "distribution dependency" do |version, type, checksum|
      subject { described_class.resolve_dependency(properties_file) }

      let(:properties_file) do
        Dependabot::DependencyFile.new(
          name: "gradle/wrapper/gradle-wrapper.properties",
          content: fixture("wrapper_files",
                           "gradle-wrapper-#{version}-#{type}#{checksum ? '-checksum' : ''}.properties")
        )
      end

      let(:dependency) do
        requirements = [{
          requirement: version,
          file: "gradle/wrapper/gradle-wrapper.properties",
          source: {
            type: "gradle-distribution",
            url: "https://services.gradle.org/distributions/gradle-#{version}-#{type}.zip",
            property: "distributionUrl"
          },
          groups: []
        }]

        if checksum
          requirements << {
            requirement: checksum,
            file: "gradle/wrapper/gradle-wrapper.properties",
            source: {
              type: "gradle-distribution",
              url: "https://services.gradle.org/distributions/gradle-#{version}-#{type}.zip.sha256",
              property: "distributionSha256Sum"
            },
            groups: []
          }
        end

        Dependabot::Dependency.new(
          name: "gradle-wrapper",
          version: version,
          requirements: requirements,
          package_manager: "gradle"
        )
      end

      it "resolved dependency is expected" do
        expect(subject).to eq(dependency)
      end
    end

    it_behaves_like "distribution dependency", "8.14.2", "all", nil
    it_behaves_like "distribution dependency", "9.0.0", "bin",
                    "8fad3d78296ca518113f3d29016617c7f9367dc005f932bd9d93bf45ba46072b"
  end
end
