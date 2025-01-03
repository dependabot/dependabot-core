# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/ecosystem"
require "dependabot/requirement"

# Define an anonymous subclass of Dependabot::Requirement for testing purposes
TestRequirement = Class.new(Dependabot::Requirement)

RSpec.describe Dependabot::Ecosystem do
  let(:package_manager_supported_versions) { [Dependabot::Version.new("1"), Dependabot::Version.new("2")] }
  let(:package_manager_deprecated_versions) { [Dependabot::Version.new("1")] }
  let(:package_manager_requirement) { TestRequirement.new(">= 1.0") }
  let(:package_manager_detected_version) { "1.0" }
  let(:package_manager_raw_version) { "1.0.1" }

  let(:language_supported_versions) { [Dependabot::Version.new("3.0"), Dependabot::Version.new("3.1")] }
  let(:language_deprecated_versions) { [Dependabot::Version.new("3.0")] }
  let(:language_requirement) { TestRequirement.new(">= 3.0") }
  let(:language_detected_version) { "3.0" }
  let(:language_raw_version) { "3.0.2" }

  let(:package_manager) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize(detected_version, raw_version, deprecated_versions, supported_versions, requirement)
        super(
          name: "bundler",
          detected_version: Dependabot::Version.new(detected_version),
          version: raw_version.nil? ? nil : Dependabot::Version.new(raw_version),
          deprecated_versions: deprecated_versions,
          supported_versions: supported_versions,
          requirement: requirement
        )
      end
    end.new(
      package_manager_detected_version,
      package_manager_raw_version,
      package_manager_deprecated_versions,
      package_manager_supported_versions,
      package_manager_requirement
    )
  end

  let(:language) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize(detected_version, raw_version, deprecated_versions, supported_versions, requirement)
        super(
          name: "ruby",
          detected_version: Dependabot::Version.new(detected_version),
          version: raw_version.nil? ? nil : Dependabot::Version.new(raw_version),
          deprecated_versions: deprecated_versions,
          supported_versions: supported_versions,
          requirement: requirement
        )
      end
    end.new(
      language_detected_version,
      language_raw_version,
      language_deprecated_versions,
      language_supported_versions,
      language_requirement
    )
  end

  describe "#initialize" do
    it "sets the correct attributes for package manager and language" do
      ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)

      expect(ecosystem.name).to eq("bundler")
      expect(ecosystem.package_manager.name).to eq("bundler")
      expect(ecosystem.package_manager.detected_version.to_s).to eq("1.0")
      expect(ecosystem.package_manager.version.to_s).to eq("1.0.1")
      expect(ecosystem.language.name).to eq("ruby")
      expect(ecosystem.language.detected_version.to_s).to eq("3.0")
      expect(ecosystem.language.version.to_s).to eq("3.0.2")
    end
  end

  describe "#name" do
    it "returns the correct name for the package manager and language" do
      ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)

      expect(ecosystem.package_manager.name).to eq("bundler")
      expect(ecosystem.language.name).to eq("ruby")
    end
  end

  describe "#version checks" do
    it "returns the correct string representation of version and raw version" do
      expect(package_manager.version.to_s).to eq("1.0.1")
      expect(language.version.to_s).to eq("3.0.2")
    end
  end

  describe "#deprecated?" do
    context "when detected version is deprecated" do
      let(:package_manager_detected_version) { "1.0" }

      context "with raw version not deprecated" do
        let(:package_manager_raw_version) { "2.0.1" }

        it "returns true" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.deprecated?).to be true
        end
      end

      context "with raw version deprecated" do
        let(:package_manager_raw_version) { "1.0.1" }

        it "returns true" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.deprecated?).to be true
        end
      end

      context "with raw version nil" do
        let(:package_manager_raw_version) { nil }

        it "returns true" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.deprecated?).to be true
        end
      end
    end

    context "when detected version is not deprecated" do
      let(:package_manager_detected_version) { "2.0" }

      context "with raw version not deprecated" do
        let(:package_manager_raw_version) { "2.0.1" }

        it "returns false" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.deprecated?).to be false
        end
      end

      context "with raw version deprecated" do
        let(:package_manager_raw_version) { "1.0.1" }

        it "returns false" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.deprecated?).to be false
        end
      end

      context "with raw version nil" do
        let(:package_manager_raw_version) { nil }

        it "returns false" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.deprecated?).to be false
        end
      end
    end
  end

  describe "#unsupported?" do
    context "when detected version is unsupported" do
      let(:package_manager_detected_version) { "0.8" }

      context "with raw version not unsupported" do
        let(:package_manager_raw_version) { "2.0.1" }

        it "returns true" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.unsupported?).to be true
        end
      end

      context "with raw version nil" do
        let(:package_manager_raw_version) { nil }

        it "returns true" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.unsupported?).to be true
        end
      end
    end

    context "when detected version is supported" do
      let(:package_manager_detected_version) { "2.0" }

      context "with raw version not unsupported" do
        let(:package_manager_raw_version) { "2.0.1" }

        it "returns false" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.unsupported?).to be false
        end
      end

      context "with raw version nil" do
        let(:package_manager_raw_version) { nil }

        it "returns false" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect(ecosystem.unsupported?).to be false
        end
      end
    end
  end

  describe "#raise_if_unsupported!" do
    context "when detected version is unsupported" do
      let(:package_manager_detected_version) { "0.8" }

      context "with raw version not nil" do
        let(:package_manager_raw_version) { "2.0.1" }

        it "raises a ToolVersionNotSupported error" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect { ecosystem.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
        end
      end

      context "with raw version nil" do
        let(:package_manager_raw_version) { nil }

        it "raises a ToolVersionNotSupported error" do
          ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
          expect { ecosystem.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
        end
      end
    end

    context "when detected version is supported" do
      let(:package_manager_detected_version) { "2.0" }

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
        expect(ecosystem.package_manager.requirement).to eq(package_manager_requirement)
        expect(ecosystem.language.requirement).to eq(language_requirement)
      end
    end

    context "when no requirement is provided" do
      let(:package_manager_requirement) { nil }
      let(:language_requirement) { nil }

      it "returns nil for the requirement" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)
        expect(ecosystem.package_manager.requirement).to be_nil
        expect(ecosystem.language.requirement).to be_nil
      end
    end
  end
end
