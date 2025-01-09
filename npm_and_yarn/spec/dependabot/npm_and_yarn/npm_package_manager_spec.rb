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
    let(:detected_version) { "6" }
    let(:raw_version) { "8.0.1" }

    it "returns false" do
      expect(package_manager.deprecated?).to be false
    end

    context "with feature flag npm_v6_deprecation_warning" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:npm_v6_deprecation_warning)
          .and_return(deprecation_enabled)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:npm_v6_unsupported_error)
          .and_return(unsupported_enabled)
      end

      context "when npm_v6_deprecation_warning is enabled and version is deprecated" do
        let(:deprecation_enabled) { true }
        let(:unsupported_enabled) { false }

        it "returns true" do
          expect(package_manager.deprecated?).to be true
        end
      end

      context "when npm_v6_deprecation_warning is enabled but version is not deprecated" do
        let(:detected_version) { "9" }
        let(:deprecation_enabled) { true }
        let(:unsupported_enabled) { false }

        it "returns false" do
          expect(package_manager.deprecated?).to be false
        end
      end

      context "when npm_v6_deprecation_warning is disabled" do
        let(:deprecation_enabled) { false }
        let(:unsupported_enabled) { false }

        it "returns false" do
          expect(package_manager.deprecated?).to be false
        end
      end

      context "when version is unsupported" do
        let(:deprecation_enabled) { true }
        let(:unsupported_enabled) { true }

        it "returns false, as unsupported takes precedence" do
          expect(package_manager.deprecated?).to be false
        end
      end
    end
  end

  describe "#unsupported?" do
    let(:detected_version) { "5" }
    let(:raw_version) { "8.0.1" }

    it "returns false for supported versions" do
      expect(package_manager.unsupported?).to be false
    end

    context "with feature flag npm_v6_unsupported_error" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:npm_v6_unsupported_error)
          .and_return(unsupported_enabled)
      end

      context "when npm_v6_unsupported_error is enabled and version is unsupported" do
        let(:detected_version) { "6" }
        let(:raw_version) { "8.0.1" }

        let(:unsupported_enabled) { true }

        it "returns true" do
          expect(package_manager.unsupported?).to be true
        end
      end

      context "when npm_v6_unsupported_error is enabled but version is supported" do
        let(:detected_version) { "7" }
        let(:raw_version) { "8.0.1" }

        let(:unsupported_enabled) { true }

        it "returns false" do
          expect(package_manager.unsupported?).to be false
        end
      end

      context "when npm_v6_unsupported_error is disabled" do
        let(:unsupported_enabled) { false }

        it "returns false" do
          expect(package_manager.unsupported?).to be false
        end
      end
    end
  end

  describe "#raise_if_unsupported!" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:npm_v6_unsupported_error)
        .and_return(unsupported_enabled)
    end

    context "when npm_v6_unsupported_error is enabled and version is unsupported" do
      let(:detected_version) { "6" }
      let(:unsupported_enabled) { true }

      it "raises a ToolVersionNotSupported error" do
        expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when npm_v6_unsupported_error is disabled" do
      let(:detected_version) { "6" }
      let(:unsupported_enabled) { false }

      it "does not raise an error" do
        expect { package_manager.raise_if_unsupported! }.not_to raise_error
      end
    end
  end
end
