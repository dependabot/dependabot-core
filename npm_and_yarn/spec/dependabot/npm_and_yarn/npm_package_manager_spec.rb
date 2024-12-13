# typed: false
# frozen_string_literal: true

require "dependabot/npm_and_yarn/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::NpmAndYarn::NpmPackageManager do
  let(:package_manager) { described_class.new(version) }

  describe "#initialize" do
    context "when version is a String" do
      let(:version) { "8" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(Dependabot::Version.new(version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::NpmAndYarn::NpmPackageManager::NAME)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(
          Dependabot::NpmAndYarn::NpmPackageManager::DEPRECATED_VERSIONS
        )
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::NpmAndYarn::NpmPackageManager::SUPPORTED_VERSIONS)
      end
    end
  end

  describe "#deprecated?" do
    let(:version) { "6" }

    it "returns false" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    let(:version) { "5" }

    it "returns false for supported versions" do
      expect(package_manager.unsupported?).to be false
    end
  end
end
