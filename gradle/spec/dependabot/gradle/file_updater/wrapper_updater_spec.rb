# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/gradle/file_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::WrapperUpdater do
  subject(:command_args) { updater.send(:command_args, target_requirements, nil) }

  let(:updater) do
    described_class.new(
      dependency_files: [],
      dependency: dependency
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "gradle-wrapper",
      version: "9.0.0",
      requirements: [
        {
          file: "gradle/wrapper/gradle-wrapper.properties",
          requirement: "9.0.0",
          groups: [],
          source: {
            type: "gradle-distribution",
            url: "https://services.gradle.org/distributions/gradle-9.0.0-bin.zip",
            property: "distributionUrl"
          }
        },
        {
          file: "subproject/gradle/wrapper/gradle-wrapper.properties",
          requirement: "9.0.0",
          groups: [],
          source: {
            type: "gradle-distribution",
            url: "https://services.gradle.org/distributions/gradle-9.0.0-all.zip",
            property: "distributionUrl"
          }
        },
        {
          file: "subproject/gradle/wrapper/gradle-wrapper.properties",
          requirement: "f759b8dd5204e2e3fa4ca3e73f452f087153cf81bac9561eeb854229cc2c5365",
          groups: [],
          source: {
            type: "gradle-distribution",
            url: "https://services.gradle.org/distributions/gradle-9.0.0-all.zip.sha256",
            property: "distributionSha256Sum"
          }
        }
      ],
      package_manager: "gradle"
    )
  end

  context "when the current wrapper file has no checksum requirement" do
    let(:target_requirements) do
      dependency.requirements.select do |req|
        req[:file] == "gradle/wrapper/gradle-wrapper.properties"
      end
    end

    it "does not crash and does not include a checksum argument from another wrapper file" do
      expect(command_args).not_to include("--gradle-distribution-sha256-sum")
      expect(command_args).to include("--distribution-type", "bin")
    end
  end
end
