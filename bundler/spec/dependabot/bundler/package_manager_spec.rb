# typed: false
# frozen_string_literal: true

require "dependabot/bundler/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Bundler::PackageManager do
  let(:package_manager) { described_class.new(detected_version, raw_version, requirement) }
  let(:requirement) { nil }

  describe "#initialize" do
    context "when version is a String" do
      let(:detected_version) { "2" }
      let(:raw_version) { "2.0.0" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(Dependabot::Bundler::Version.new(raw_version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::Bundler::PACKAGE_MANAGER)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(Dependabot::Bundler::DEPRECATED_BUNDLER_VERSIONS)
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::Bundler::SUPPORTED_BUNDLER_VERSIONS)
      end
    end

    context "when version is a Dependabot::Bundler::Version" do
      let(:detected_version) { "2" }
      let(:raw_version) { "2" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(raw_version)
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::Bundler::PACKAGE_MANAGER)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(Dependabot::Bundler::DEPRECATED_BUNDLER_VERSIONS)
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::Bundler::SUPPORTED_BUNDLER_VERSIONS)
      end
    end

    context "when a requirement is provided" do
      let(:detected_version) { "2.1" }
      let(:raw_version) { "2.1.2" }
      let(:requirement) { Dependabot::Bundler::Requirement.new(">= 1.12.0, ~> 2.3.0") }

      it "sets the requirement correctly" do
        expect(package_manager.requirement.to_s).to eq(">= 1.12.0, ~> 2.3.0")
      end

      it "calculates the correct min_version" do
        expect(package_manager.requirement.min_version).to eq(Dependabot::Version.new("2.3.0"))
      end

      it "calculates the correct max_version" do
        expect(package_manager.requirement.max_version).to eq(Dependabot::Version.new("2.4.0"))
      end
    end

    context "when a single minimum constraint is provided" do
      let(:detected_version) { "2.1" }
      let(:raw_version) { "2.1.2" }
      let(:requirement) { Dependabot::Bundler::Requirement.new(">= 1.5") }

      it "sets the requirement correctly" do
        expect(package_manager.requirement.to_s).to eq(">= 1.5")
      end

      it "calculates the correct min_version" do
        expect(package_manager.requirement.min_version).to eq(Dependabot::Version.new("1.5"))
      end

      it "returns nil for max_version" do
        expect(package_manager.requirement.max_version).to be_nil
      end
    end

    context "when multiple maximum constraints are provided" do
      let(:detected_version) { "2.1" }
      let(:raw_version) { "2.1.2" }
      let(:requirement) { Dependabot::Bundler::Requirement.new("<= 2.5, < 3.0") }

      it "sets the requirement correctly" do
        expect(package_manager.requirement.to_s).to eq("<= 2.5, < 3.0")
      end

      it "calculates the correct max_version" do
        expect(package_manager.requirement.max_version).to eq(Dependabot::Version.new("2.5"))
      end

      it "returns nil for min_version" do
        expect(package_manager.requirement.min_version).to be_nil
      end
    end
  end

  describe "SUPPORTED_BUNDLER_VERSIONS" do
    it "is in ascending order" do
      expect(Dependabot::Bundler::SUPPORTED_BUNDLER_VERSIONS)
        .to eq(Dependabot::Bundler::SUPPORTED_BUNDLER_VERSIONS.sort)
    end
  end

  describe "#deprecated?" do
    context "when version is deprecated but not unsupported" do
      let(:detected_version) { "1" }
      let(:raw_version) { "1" }

      it "returns true" do
        allow(package_manager).to receive_messages(deprecated?: true)
        expect(package_manager.deprecated?).to be true
      end
    end

    context "when version is unsupported" do
      let(:detected_version) { "0.9" }
      let(:raw_version) { "0.9" }

      it "returns false, as unsupported takes precedence" do
        expect(package_manager.deprecated?).to be false
      end
    end
  end

  describe "#unsupported?" do
    context "when version is supported" do
      let(:detected_version) { "2" }
      let(:raw_version) { "2" }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end

    context "when version is not supported" do
      let(:detected_version) { "0.9" }
      let(:raw_version) { "0.9" }

      it "returns true" do
        expect(package_manager.unsupported?).to be true
      end
    end
  end

  describe "#raise_if_unsupported!" do
    context "when version is unsupported" do
      let(:detected_version) { "0.9" }
      let(:raw_version) { "0.9" }

      it "raises a ToolVersionNotSupported error" do
        expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when version is supported" do
      let(:detected_version) { "2.1" }
      let(:raw_version) { "2.1" }

      it "does not raise an error" do
        expect { package_manager.raise_if_unsupported! }.not_to raise_error
      end
    end
  end
end
