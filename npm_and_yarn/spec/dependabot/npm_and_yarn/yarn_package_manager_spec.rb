# typed: false
# frozen_string_literal: true

require "dependabot/npm_and_yarn/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::NpmAndYarn::YarnPackageManager do
  let(:package_manager) { described_class.new(detected_version, raw_version) }

  describe "#initialize" do
    context "when version is a String" do
      let(:detected_version) { "2" }
      let(:raw_version) { "2.1.0" }

      it "sets the detected version and version correctly" do
        expect(package_manager.version).to eq(Dependabot::Version.new(raw_version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::NpmAndYarn::YarnPackageManager::NAME)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(
          Dependabot::NpmAndYarn::YarnPackageManager::DEPRECATED_VERSIONS
        )
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::NpmAndYarn::YarnPackageManager::SUPPORTED_VERSIONS)
      end
    end
  end

  describe "#deprecated?" do
    let(:detected_version) { "1" }
    let(:raw_version) { "1.1.0" }

    it "returns false" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    let(:detected_version) { "4" }
    let(:raw_version) { "4.1.0" }

    it "returns false for supported versions" do
      expect(package_manager.unsupported?).to be false
    end
  end
end
