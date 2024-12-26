# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/ecosystem"

RSpec.describe Dependabot::Ecosystem::VersionManager do # rubocop:disable RSpec/FilePath,RSpec/SpecFilePathFormat
  let(:concrete_class) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize
        detected_version = "1.0.0"
        raw_version = "1.0.0"
        super(
          "bundler", # name
          Dependabot::Version.new(detected_version), # version
          Dependabot::Version.new(raw_version), # version
          [Dependabot::Version.new("1")], # deprecated_versions
          [Dependabot::Version.new("1"), Dependabot::Version.new("2")] # supported_versions
        )
      end

      def support_later_versions?
        true
      end
    end
  end

  let(:default_concrete_class) do
    Class.new(Dependabot::Ecosystem::VersionManager) do
      def initialize
        detected_version = "1.0.0"
        raw_version = "1.0.0"
        super(
          "bundler", # name
          Dependabot::Version.new(detected_version),
          Dependabot::Version.new(raw_version)
        )
      end
    end
  end

  let(:package_manager) { concrete_class.new }
  let(:default_package_manager) { default_concrete_class.new }

  describe "#name" do
    it "returns the name of the package manager" do
      expect(package_manager.name).to eq("bundler")
    end
  end

  describe "#version" do
    it "returns the version of the package manager" do
      expect(package_manager.version).to eq(Dependabot::Version.new("1.0.0"))
    end
  end

  describe "#deprecated_versions" do
    it "returns an array of deprecated versions" do
      expect(package_manager.deprecated_versions).to eq([Dependabot::Version.new("1")])
    end

    it "returns an empty array by default" do
      expect(default_package_manager.deprecated_versions).to eq([])
    end
  end

  describe "#supported_versions" do
    it "returns an array of supported versions" do
      expect(package_manager.supported_versions).to eq([
        Dependabot::Version.new("1"),
        Dependabot::Version.new("2")
      ])
    end

    it "returns an empty array by default" do
      expect(default_package_manager.supported_versions).to eq([])
    end

    it "is in ascending order" do
      expect(package_manager.supported_versions).to eq(package_manager.supported_versions.sort)
    end
  end

  describe "#deprecated?" do
    context "when version is deprecated but not unsupported" do
      let(:version) { Dependabot::Version.new("1") }

      it "returns true" do
        package_manager.instance_variable_set(:@version, version)
        package_manager.instance_variable_set(:@supported_versions,
                                              [Dependabot::Version.new("1"), Dependabot::Version.new("2")])
        expect(package_manager.deprecated?).to be true
      end
    end

    context "when version is unsupported" do
      let(:detected_version) { Dependabot::Version.new("0.9") }
      let(:raw_version) { Dependabot::Version.new("0.9.0") }

      it "returns false as unsupported takes precedence" do
        package_manager.instance_variable_set(:@detected_version, detected_version)
        package_manager.instance_variable_set(:@version, raw_version)
        package_manager.instance_variable_set(:@supported_versions,
                                              [Dependabot::Version.new("1"), Dependabot::Version.new("2")])
        expect(package_manager.deprecated?).to be false
      end
    end
  end

  describe "#unsupported?" do
    context "when version is unsupported" do
      let(:detected_version) { Dependabot::Version.new("0.9") }
      let(:raw_version) { Dependabot::Version.new("0.9.0") }

      it "returns true" do
        package_manager.instance_variable_set(:@detected_version, detected_version)
        package_manager.instance_variable_set(:@version, raw_version)
        package_manager.instance_variable_set(:@supported_versions,
                                              [Dependabot::Version.new("1"), Dependabot::Version.new("2")])
        expect(package_manager.unsupported?).to be true
      end
    end

    context "when version is supported" do
      let(:version) { Dependabot::Version.new("2.0.0") }

      it "returns false" do
        package_manager.instance_variable_set(:@version, version)
        package_manager.instance_variable_set(:@supported_versions,
                                              [Dependabot::Version.new("1"), Dependabot::Version.new("2")])
        expect(package_manager.unsupported?).to be false
      end
    end

    context "when there is no list of supported versions" do
      it "returns false" do
        expect(default_package_manager.unsupported?).to be false
      end
    end
  end

  describe "#support_later_versions?" do
    it "returns true if the package manager supports later versions" do
      expect(package_manager.support_later_versions?).to be true
    end

    it "returns false by default" do
      expect(default_package_manager.support_later_versions?).to be false
    end
  end
end
