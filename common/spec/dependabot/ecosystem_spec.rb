# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/ecosystem"

RSpec.describe Dependabot::Ecosystem do
  let(:supported_versions) { [Dependabot::Version.new("1"), Dependabot::Version.new("2")] }
  let(:deprecated_versions) { [Dependabot::Version.new("1")] }

  let(:package_manager_raw_version) { "1.0.0" }
  let(:language_raw_version) { "3.0.0" }

  let(:package_manager) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize(raw_version, deprecated_versions, supported_versions)
        super(
          "bundler", # name
          raw_version,
          Dependabot::Version.new(raw_version), # version
          deprecated_versions, # deprecated_versions
          supported_versions # supported_versions
        )
      end
    end.new(package_manager_raw_version, deprecated_versions, supported_versions)
  end

  let(:language) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize(raw_version)
        super(
          "ruby", # name
          raw_version,
          Dependabot::Version.new(raw_version) # version
        )
      end
    end.new(language_raw_version)
  end

  describe "#initialize" do
    it "sets the correct attributes" do
      ecosystem = described_class.new(name: "bundler", package_manager: package_manager, language: language)

      expect(ecosystem.name).to eq("bundler")
      expect(ecosystem.package_manager.name).to eq("bundler")
      expect(ecosystem.language.name).to eq("ruby")
    end
  end

  describe "#deprecated?" do
    context "when the package manager version is deprecated" do
      let(:package_manager_raw_version) { "1" }

      it "returns true" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager)
        expect(ecosystem.deprecated?).to be true
      end
    end

    context "when the package manager version is not deprecated" do
      let(:package_manager_raw_version) { "2.0.0" }

      it "returns false" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager)
        expect(ecosystem.deprecated?).to be false
      end
    end
  end

  describe "#unsupported?" do
    context "when the package manager version is unsupported" do
      let(:package_manager_raw_version) { "0.8.0" }

      it "returns true" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager)
        expect(ecosystem.unsupported?).to be true
      end
    end

    context "when the package manager version is supported" do
      let(:package_manager_raw_version) { "2.0.0" }

      it "returns false" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager)
        expect(ecosystem.unsupported?).to be false
      end
    end
  end

  describe "#raise_if_unsupported!" do
    context "when the package manager version is unsupported" do
      let(:package_manager_raw_version) { "0.8.0" }

      it "raises a ToolVersionNotSupported error" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager)
        expect { ecosystem.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when the package manager version is supported" do
      let(:package_manager_raw_version) { "2.0.0" }

      it "does not raise an error" do
        ecosystem = described_class.new(name: "bundler", package_manager: package_manager)
        expect { ecosystem.raise_if_unsupported! }.not_to raise_error
      end
    end
  end
end
