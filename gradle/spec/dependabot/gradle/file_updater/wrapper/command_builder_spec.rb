# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/file_updater"
require "dependabot/gradle/version"

RSpec.describe Dependabot::Gradle::FileUpdater::Wrapper::CommandBuilder do
  subject(:args) do
    described_class.new(
      requirements: requirements,
      original_properties: original_properties,
      gradle_version: gradle_version
    ).build
  end

  let(:original_properties) { nil }
  let(:gradle_version) { nil }

  let(:requirements) do
    [{
      file: "gradle/wrapper/gradle-wrapper.properties",
      requirement: "9.0.0",
      groups: [],
      source: {
        type: "gradle-distribution",
        url: "https://services.gradle.org/distributions/gradle-9.0.0-bin.zip",
        property: "distributionUrl"
      }
    }]
  end

  it "always requests the target version and skips URL validation" do
    expect(args).to include("wrapper", "--gradle-version", "9.0.0", "--no-validate-url")
  end

  it "derives the distribution type from the URL" do
    expect(args).to include("--distribution-type", "bin")
  end

  context "with a checksum requirement" do
    let(:requirements) do
      super() + [{
        file: "gradle/wrapper/gradle-wrapper.properties",
        requirement: "deadbeef",
        groups: [],
        source: {
          type: "gradle-distribution",
          url: "https://services.gradle.org/distributions/gradle-9.0.0-bin.zip",
          property: "distributionSha256Sum"
        }
      }]
    end

    it "passes the checksum" do
      expect(args).to include("--gradle-distribution-sha256-sum", "deadbeef")
    end
  end

  context "without a checksum requirement" do
    it "does not pass a checksum flag" do
      expect(args).not_to include("--gradle-distribution-sha256-sum")
    end
  end

  context "with original properties and a supporting executing version" do
    let(:gradle_version) { Dependabot::Gradle::Version.new("9.5.0") }
    let(:original_properties) do
      Dependabot::Gradle::FileUpdater::Wrapper::PropertiesDocument.parse(
        <<~PROPS
          networkTimeout=20000
          retries=3
          retryBackOffMs=1000
        PROPS
      )
    end

    it "forwards the user's gated settings" do
      expect(args).to include("--network-timeout", "20000")
      expect(args).to include("--retries", "3")
      expect(args).to include("--retry-back-off-ms", "1000")
    end
  end

  context "when the executing version does not support the gated flags" do
    let(:gradle_version) { Dependabot::Gradle::Version.new("9.0.0") }
    let(:original_properties) do
      Dependabot::Gradle::FileUpdater::Wrapper::PropertiesDocument.parse(
        <<~PROPS
          networkTimeout=20000
          retries=3
          retryBackOffMs=1000
        PROPS
      )
    end

    it "forwards only the supported flags" do
      expect(args).to include("--network-timeout", "20000")
      expect(args).not_to include("--retries")
      expect(args).not_to include("--retry-back-off-ms")
    end
  end

  context "when the executing version is unknown" do
    let(:gradle_version) { nil }
    let(:original_properties) do
      Dependabot::Gradle::FileUpdater::Wrapper::PropertiesDocument.parse("retries=3\nnetworkTimeout=20000\n")
    end

    it "omits all version-gated flags" do
      expect(args).not_to include("--retries")
      expect(args).not_to include("--network-timeout")
    end
  end

  context "when a steered property is present but blank" do
    let(:gradle_version) { Dependabot::Gradle::Version.new("9.5.0") }
    let(:original_properties) do
      Dependabot::Gradle::FileUpdater::Wrapper::PropertiesDocument.parse("retries=\nnetworkTimeout=   \n")
    end

    it "does not emit flags with empty values" do
      expect(args).not_to include("--retries")
      expect(args).not_to include("--network-timeout")
    end
  end

  context "with a custom mirror URL that omits the bin/all marker" do
    let(:requirements) do
      [{
        file: "gradle/wrapper/gradle-wrapper.properties",
        requirement: "9.0.0",
        groups: [],
        source: {
          type: "gradle-distribution",
          url: "https://mirror.example.com/gradle-9.0.0.zip",
          property: "distributionUrl"
        }
      }]
    end

    it "omits the distribution-type flag" do
      expect(args).not_to include("--distribution-type")
    end
  end
end
