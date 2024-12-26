# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/ecosystem"
require "dependabot/requirement"

# Define an anonymous subclass of Dependabot::Requirement for testing purposes
TestRequirement = Class.new(Dependabot::Requirement)

RSpec.describe Dependabot::Ecosystem do
  let(:supported_versions) { [Dependabot::Version.new("1"), Dependabot::Version.new("2")] }
  let(:deprecated_versions) { [Dependabot::Version.new("1")] }
  let(:requirement) { TestRequirement.new(">= 1.0") }

  let(:package_manager_detected_version) { "1.0.0" }
  let(:package_manager_raw_version) { "1.0.0" }
  let(:language_detected_version) { "3.0.0" }
  let(:language_raw_version) { "3.0.0" }

  let(:package_manager) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize(detected_version, raw_version, deprecated_versions, supported_versions, requirement)
        super(
          "bundler", # name
          Dependabot::Version.new(detected_version), # version
          Dependabot::Version.new(raw_version), # version
          deprecated_versions, # deprecated_versions
          supported_versions, # supported_versions
          requirement # requirement
        )
      end
    end.new(package_manager_detected_version, package_manager_raw_version, deprecated_versions, supported_versions, requirement)
  end

  let(:language) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize(detected_version, raw_version)
        super(
          "ruby", # name
          Dependabot::Version.new(detected_version), # version
          Dependabot::Version.new(raw_version), # version
          [], # deprecated_versions
          [], # supported_versions
          nil # requirement
        )
      end
    end.new(language_detected_version, language_raw_version)
  end

  describe "#initialize" do
    it "sets the correct attributes" do
      ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)

      expect(ecosystem.name).to eq("bundler")
      expect(ecosystem.package_manager.name).to eq("bundler")
      expect(ecosystem.language.name).to eq("ruby")
    end
  end

  describe "#deprecated?" do
    context "when the package manager version is deprecated" do
      let(:package_manager_detected_version) { "1" }
      let(:package_manager_raw_version) { "1" }

      it "returns true" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
        expect(ecosystem.deprecated?).to be true
      end
    end

    context "when the package manager version is not deprecated" do
      let(:package_manager_detected_version) { "2.0.0" }
      let(:package_manager_raw_version) { "2.0.0" }

      it "returns false" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
        expect(ecosystem.deprecated?).to be false
      end
    end
  end

  describe "#unsupported?" do
    context "when the package manager version is unsupported" do
      let(:package_manager_detected_version) { "0.8.0" }
      let(:package_manager_raw_version) { "0.8.0" }

      it "returns true" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
        expect(ecosystem.unsupported?).to be true
      end
    end

    context "when the package manager version is supported" do
      let(:package_manager_detected_version) { "2.0.0" }
      let(:package_manager_raw_version) { "2.0.0" }

      it "returns false" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
        expect(ecosystem.unsupported?).to be false
      end
    end
  end

  describe "#raise_if_unsupported!" do
    context "when the package manager version is unsupported" do
      let(:package_manager_detected_version) { "0.8.0" }
      let(:package_manager_raw_version) { "0.8.0" }

      it "raises a ToolVersionNotSupported error" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
        expect { ecosystem.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when the package manager version is supported" do
      let(:package_manager_detected_version) { "2.0.0" }
      let(:package_manager_raw_version) { "2.0.0" }

      it "does not raise an error" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
        expect { ecosystem.raise_if_unsupported! }.not_to raise_error
      end
    end
  end

  describe "#requirement" do
    context "when a requirement is provided" do
      it "sets the requirement correctly" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
        expect(ecosystem.package_manager.requirement).to eq(requirement)
      end
    end

    context "when no requirement is provided" do
      let(:requirement) { nil }

      it "returns nil for the requirement" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
        expect(ecosystem.package_manager.requirement).to be_nil
      end
    end
  end
end
