# typed: false
# frozen_string_literal: true

require "dependabot/npm_and_yarn/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::NpmAndYarn::NpmPackageManager do
  let(:package_manager) do
    described_class.new(
      detected_version: detected_version,
      raw_version: raw_version
    )
  end

  let(:detected_version) { "8" }
  let(:raw_version) { "9.5.1" }

  describe "#initialize" do
    context "when version is a String" do
      let(:detected_version) { "8" }
      let(:raw_version) {  "9.5.1" }

      it "sets the version correctly" do
        expect(package_manager.detected_version).to eq(Dependabot::Version.new(detected_version))
        expect(package_manager.version).to eq(Dependabot::Version.new(raw_version))
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
    it "returns false" do
      expect(package_manager.deprecated?).to be false
    end

    context "when detected version is unsupported" do
      let(:detected_version) { "6" }

      it "returns false as unsupported takes precedence" do
        expect(package_manager.deprecated?).to be false
      end
    end

    context "when detected version is deprecated but not unsupported" do
      let(:detected_version) { "6" }

      before do
        allow(package_manager).to receive(:unsupported?).and_return(false)
      end

      it "returns true" do
        expect(package_manager.deprecated?).to be true
      end
    end
  end

  describe "#unsupported?" do
    it "returns false" do
      expect(package_manager.unsupported?).to be false
    end

    context "when version is unsupported" do
      let(:detected_version) { "6" }

      it "returns true" do
        expect(package_manager.unsupported?).to be true
      end
    end
  end

  describe "#raise_if_unsupported!" do
    it "does not raise error" do
      expect { package_manager.raise_if_unsupported! }.not_to raise_error
    end

    context "when detected version is deprecated" do
      let(:detected_version) { "6" }

      it "raises a ToolVersionNotSupported error" do
        expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end
  end
end
