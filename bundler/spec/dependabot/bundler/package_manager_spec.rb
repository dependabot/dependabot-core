# typed: false
# frozen_string_literal: true

require "dependabot/bundler/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Bundler::PackageManager do
  let(:package_manager) do
    described_class.new(
      detected_version: detected_version,
      raw_version: raw_version,
      requirement: requirement
    )
  end
  let(:requirement) { nil }

  describe "#initialize" do
    context "when versions are set" do
      let(:detected_version) { "2" }
      let(:raw_version) { "2.0.1" }

      it "sets detected and raw versions correctly" do
        expect(package_manager.detected_version).to eq(Dependabot::Bundler::Version.new(detected_version))
        expect(package_manager.version).to eq(Dependabot::Bundler::Version.new(raw_version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::Bundler::PACKAGE_MANAGER)
      end

      it "sets deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(Dependabot::Bundler::DEPRECATED_BUNDLER_VERSIONS)
      end

      it "sets supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::Bundler::SUPPORTED_BUNDLER_VERSIONS)
      end
    end

    context "when a requirement is provided" do
      let(:detected_version) { "2.1" }
      let(:raw_version) { "2.1.3" }
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
  end

  describe "#deprecated?" do
    context "when detected_version is deprecated but raw_version is not" do
      let(:detected_version) { "1" }
      let(:raw_version) { "2.0.1" }

      it "returns false because no deprecated versions exist" do
        allow(package_manager).to receive(:unsupported?).and_return(false)
        expect(package_manager.deprecated?).to be false
      end
    end

    context "when detected_version and raw_version are both deprecated" do
      let(:detected_version) { "1" }
      let(:raw_version) { "1.0.3" }

      it "returns false because no deprecated versions exist" do
        allow(package_manager).to receive(:unsupported?).and_return(false)
        expect(package_manager.deprecated?).to be false
      end
    end

    context "when detected_version is unsupported" do
      let(:detected_version) { "0.9" }
      let(:raw_version) { "1.0.4" }

      it "returns false, as unsupported takes precedence" do
        expect(package_manager.deprecated?).to be false
      end
    end

    context "when raw_version is nil" do
      let(:detected_version) { "1" }
      let(:raw_version) { nil }

      it "returns false because no deprecated versions exist" do
        allow(package_manager).to receive(:unsupported?).and_return(false)
        expect(package_manager.deprecated?).to be false
      end
    end
  end

  describe "#unsupported?" do
    context "when detected_version is supported" do
      let(:detected_version) { "2" }
      let(:raw_version) { "2.1.3" }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end

    context "when detected_version is unsupported" do
      let(:detected_version) { "0.9" }
      let(:raw_version) { "0.9.2" }

      it "returns true" do
        expect(package_manager.unsupported?).to be true
      end
    end

    context "when raw_version is nil" do
      let(:detected_version) { "0.9" }
      let(:raw_version) { nil }

      it "returns true based on detected_version" do
        expect(package_manager.unsupported?).to be true
      end
    end
  end

  describe "#raise_if_unsupported!" do
    context "when detected_version is unsupported" do
      let(:detected_version) { "0.9" }
      let(:raw_version) { "0.9.2" }

      it "raises a ToolVersionNotSupported error" do
        expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when detected_version is supported" do
      let(:detected_version) { "2.1" }
      let(:raw_version) { "2.1.4" }

      it "does not raise an error" do
        expect { package_manager.raise_if_unsupported! }.not_to raise_error
      end
    end

    context "when raw_version is nil but detected_version is unsupported" do
      let(:detected_version) { "0.9" }
      let(:raw_version) { nil }

      it "raises a ToolVersionNotSupported error" do
        expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end
  end

  describe "SUPPORTED_BUNDLER_VERSIONS" do
    it "is in ascending order" do
      expect(Dependabot::Bundler::SUPPORTED_BUNDLER_VERSIONS)
        .to eq(Dependabot::Bundler::SUPPORTED_BUNDLER_VERSIONS.sort)
    end
  end
end
