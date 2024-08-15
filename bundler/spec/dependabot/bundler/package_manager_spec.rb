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

  describe "#deprecated?" do
    context "when version is deprecated?" do
      let(:version) { "1" }

      it "returns true" do
        expect(package_manager.deprecated?).to be true
      end
    end

    context "when version is not deprecated" do
      let(:version) { "2" }

      it "returns false" do
        expect(package_manager.deprecated?).to be false
      end
    end
  end

  describe "#unsupported" do
    context "when version is deprecated?" do
      let(:version) { "1" }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end

    context "when version is supported" do
      let(:version) { "2" }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end

    context "when version is unsupported?" do
      let(:version) { "0.9" }

      it "returns true" do
        expect(package_manager.unsupported?).to be true
      end
    end
  end

  describe "#supported_versions" do
    context "when there are supported versions" do
      let(:version) { "2" }

      it "returns the correct supported versions" do
        expect(package_manager.supported_versions).to eq([Dependabot::Bundler::Version.new("2")])
      end
    end
  end

  describe "#deprecated_versions" do
    context "when there are deprecated versions" do
      let(:version) { "2" }

      it "returns the correct deprecated versions" do
        expect(package_manager.deprecated_versions).to eq([Dependabot::Bundler::Version.new("1")])
      end
    end
  end
end
