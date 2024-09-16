# typed: false
# frozen_string_literal: true

require "dependabot/bundler/package_manager"
require "dependabot/package_manager"
require "spec_helper"

RSpec.describe Dependabot::Bundler::PackageManager do
  let(:package_manager) { described_class.new(version) }

  describe "#initialize" do
    context "when version is a String" do
      let(:version) { "2" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(Dependabot::Bundler::Version.new(version))
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
      let(:version) { Dependabot::Bundler::Version.new("2") }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(version)
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
  end

  describe "SUPPORTED_BUNDLER_VERSIONS" do
    it "is in ascending order" do
      expect(Dependabot::Bundler::SUPPORTED_BUNDLER_VERSIONS)
        .to eq(Dependabot::Bundler::SUPPORTED_BUNDLER_VERSIONS.sort)
    end
  end

  describe "#deprecated?" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:bundler_v1_unsupported_error)
        .and_return(feature_flag_enabled)
    end

    context "when version is deprecated but not unsupported" do
      let(:version) { "1" }
      let(:feature_flag_enabled) { false }

      it "returns true" do
        expect(package_manager.deprecated?).to be true
      end
    end

    context "when version is unsupported" do
      let(:version) { "0.9" }
      let(:feature_flag_enabled) { true }

      it "returns false, as unsupported takes precedence" do
        expect(package_manager.deprecated?).to be false
      end
    end
  end

  describe "#unsupported?" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:bundler_v1_unsupported_error)
        .and_return(feature_flag_enabled)
    end

    context "when feature flag is enabled and version is unsupported" do
      let(:version) { "0.9" }
      let(:feature_flag_enabled) { true }

      it "returns true" do
        expect(package_manager.unsupported?).to be true
      end
    end

    context "when feature flag is enabled and version is supported" do
      let(:version) { "2" }
      let(:feature_flag_enabled) { true }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end

    context "when feature flag is disabled" do
      let(:version) { "0.9" }
      let(:feature_flag_enabled) { false }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end
  end

  describe "#raise_if_unsupported!" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:bundler_v1_unsupported_error)
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
