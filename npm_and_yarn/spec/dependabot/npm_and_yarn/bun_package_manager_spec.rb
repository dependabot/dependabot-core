# typed: false
# frozen_string_literal: true

require "dependabot/npm_and_yarn/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::NpmAndYarn::BunPackageManager do
  let(:package_manager) do
    described_class.new(
      detected_version: detected_version,
      raw_version: raw_version
    )
  end

  let(:detected_version) { "1" }
  let(:raw_version) { "1.1.39" }

  describe "#initialize" do
    context "when version is a String" do
      it "sets the version correctly" do
        expect(package_manager.detected_version).to eq(Dependabot::Version.new(detected_version))
        expect(package_manager.version).to eq(Dependabot::Version.new(raw_version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::NpmAndYarn::BunPackageManager::NAME)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(
          Dependabot::NpmAndYarn::BunPackageManager::DEPRECATED_VERSIONS
        )
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::NpmAndYarn::BunPackageManager::SUPPORTED_VERSIONS)
      end
    end
  end

  describe "#deprecated?" do
    it "returns false" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    context "when version is the minimum supported version" do
      let(:detected_version) { Dependabot::NpmAndYarn::BunPackageManager::MIN_SUPPORTED_VERSION.to_s }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end

    context "when version is unsupported" do
      let(:raw_version) { "1.1.38" }

      it "returns true" do
        expect(package_manager.unsupported?).to be true
      end
    end
  end
end
