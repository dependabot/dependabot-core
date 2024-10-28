# typed: false
# frozen_string_literal: true

require "dependabot/composer/package_manager"
require "dependabot/package_manager"
require "spec_helper"

RSpec.describe Dependabot::Composer::PackageManager do
  let(:package_manager) { described_class.new(version) }

  describe "#initialize" do
    context "when version is a String" do
      let(:version) { "2" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(Dependabot::Version.new(version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::Composer::PACKAGE_MANAGER)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(Dependabot::Composer::DEPRECATED_COMPOSER_VERSIONS)
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::Composer::SUPPORTED_COMPOSER_VERSIONS)
      end
    end

    context "when version is a Dependabot::Version" do
      let(:version) { Dependabot::Version.new("2") }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(version)
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::Composer::PACKAGE_MANAGER)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(Dependabot::Composer::DEPRECATED_COMPOSER_VERSIONS)
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::Composer::SUPPORTED_COMPOSER_VERSIONS)
      end
    end
  end

  describe "SUPPORTED_COMPOSER_VERSIONS" do
    it "is in ascending order" do
      expect(Dependabot::Composer::SUPPORTED_COMPOSER_VERSIONS)
        .to eq(Dependabot::Composer::SUPPORTED_COMPOSER_VERSIONS.sort)
    end
  end

  describe "#deprecated?" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:composer_v1_deprecation_warning)
        .and_return(feature_flag_deprecation_enabled)
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:composer_v1_unsupported_error)
        .and_return(feature_flag_unsupported_enabled)
    end

    context "when feature flag `composer_v1_deprecation_warning` is enabled and version is deprecated" do
      let(:version) { "1" }
      let(:feature_flag_deprecation_enabled) { true }
      let(:feature_flag_unsupported_enabled) { false }

      it "returns true" do
        expect(package_manager.deprecated?).to be true
      end
    end

    context "when feature flag `composer_v1_deprecation_warning` is disabled" do
      let(:version) { "1" }
      let(:feature_flag_deprecation_enabled) { false }
      let(:feature_flag_unsupported_enabled) { false }

      it "returns false" do
        expect(package_manager.deprecated?).to be false
      end
    end

    context "when version is unsupported and takes precedence" do
      let(:version) { "0.9" }
      let(:feature_flag_deprecation_enabled) { true }
      let(:feature_flag_unsupported_enabled) { true }

      it "returns false, as unsupported takes precedence" do
        expect(package_manager.deprecated?).to be false
      end
    end
  end

  describe "#unsupported?" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:composer_v1_unsupported_error)
        .and_return(feature_flag_unsupported_enabled)
    end

    context "when feature flag `composer_v1_unsupported_error` is enabled and version is unsupported" do
      let(:version) { "0.9" }
      let(:feature_flag_unsupported_enabled) { true }

      it "returns true" do
        expect(package_manager.unsupported?).to be true
      end
    end

    context "when feature flag `composer_v1_unsupported_error` is disabled" do
      let(:version) { "0.9" }
      let(:feature_flag_unsupported_enabled) { false }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end

    context "when feature flag is enabled and version is supported" do
      let(:version) { "2" }
      let(:feature_flag_unsupported_enabled) { true }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end
  end

  describe "#raise_if_unsupported!" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:composer_v1_unsupported_error)
        .and_return(feature_flag_enabled)
    end

    context "when feature flag is enabled and version is unsupported" do
      let(:version) { "0.9" }
      let(:feature_flag_enabled) { true }

      it "raises a ToolVersionNotSupported error" do
        expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when feature flag is disabled" do
      let(:version) { "0.9" }
      let(:feature_flag_enabled) { false }

      it "does not raise an error" do
        expect { package_manager.raise_if_unsupported! }.not_to raise_error
      end
    end
  end
end
