# typed: false
# frozen_string_literal: true

require "dependabot/elm/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Elm::PackageManager do
  let(:package_manager) { described_class.new(version, requirement) }
  let(:version) { "0.19.1" }
  let(:requirement) { nil }

  describe "#initialize" do
    context "when version is a String" do
      it "sets the version correctly" do
        expect(package_manager.version).to eq(Dependabot::Elm::Version.new(version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::Elm::PACKAGE_MANAGER)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(Dependabot::Elm::DEPRECATED_ELM_VERSIONS)
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::Elm::SUPPORTED_ELM_VERSIONS)
      end
    end

    context "when a requirement is provided" do
      let(:requirement) { Dependabot::Elm::Requirement.new(">= 0.19.0, < 0.20.0") }

      it "sets the requirement correctly" do
        expect(package_manager.requirement.to_s).to eq(">= 0.19.0, < 0.20.0")
      end

      it "calculates the correct min_version" do
        expect(package_manager.requirement.min_version).to eq(Dependabot::Version.new("0.19.0"))
      end

      it "calculates the correct max_version" do
        expect(package_manager.requirement.max_version).to eq(Dependabot::Version.new("0.20.0"))
      end
    end
  end

  describe "#deprecated?" do
    it "returns false" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    it "returns false" do
      expect(package_manager.unsupported?).to be false
    end
  end
end
