# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/file_updater"
require "dependabot/gradle/version"

RSpec.describe Dependabot::Gradle::FileUpdater::Wrapper::ExecutingVersionDetector do
  describe ".from_distribution_url" do
    it "parses the version from a distribution URL" do
      url = "https://services.gradle.org/distributions/gradle-9.5.0-bin.zip"
      expect(described_class.from_distribution_url(url)).to eq(Dependabot::Gradle::Version.new("9.5.0"))
    end

    it "parses the version from an escaped, -all distribution URL" do
      url = "https\\://services.gradle.org/distributions/gradle-8.14.2-all.zip"
      expect(described_class.from_distribution_url(url)).to eq(Dependabot::Gradle::Version.new("8.14.2"))
    end

    it "parses an rc/milestone version" do
      url = "https://services.gradle.org/distributions/gradle-9.5.0-rc-1-bin.zip"
      expect(described_class.from_distribution_url(url)).to eq(Dependabot::Gradle::Version.new("9.5.0-rc-1"))
    end

    it "does not mistake host/port numbers for the version" do
      url = "https://192.168.0.1:8080/dist/gradle-9.0.0-bin.zip"
      expect(described_class.from_distribution_url(url)).to eq(Dependabot::Gradle::Version.new("9.0.0"))
    end

    it "returns nil for nil or unparseable URLs" do
      expect(described_class.from_distribution_url(nil)).to be_nil
      expect(described_class.from_distribution_url("https://example.com/not-a-gradle-dist")).to be_nil
      expect(described_class.from_distribution_url("https://mirror.example.com/gradle-9.0.0.zip")).to be_nil
    end
  end

  describe ".from_version_output" do
    it "parses the version from `gradle --version` output" do
      output = <<~OUT
        ------------------------------------------------------------
        Gradle 9.2.1
        ------------------------------------------------------------
      OUT
      expect(described_class.from_version_output(output)).to eq(Dependabot::Gradle::Version.new("9.2.1"))
    end

    it "returns nil when no version line is present" do
      expect(described_class.from_version_output("no version here")).to be_nil
      expect(described_class.from_version_output(nil)).to be_nil
    end
  end
end
