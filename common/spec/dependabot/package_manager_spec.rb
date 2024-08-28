# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package_manager"

RSpec.describe Dependabot::PackageManagerBase do # rubocop:disable RSpec/FilePath,RSpec/SpecFilePathFormat
  let(:concrete_class) do
    Class.new(Dependabot::PackageManagerBase) do
      def name
        "bundler"
      end

      def version
        Dependabot::Version.new("1.0.0")
      end

      def deprecated_versions
        [Dependabot::Version.new("1")]
      end

      def unsupported_versions
        [Dependabot::Version.new("0")]
      end

      def supported_versions
        [Dependabot::Version.new("1"), Dependabot::Version.new("2")]
      end

      def support_later_versions?
        true
      end
    end
  end

  let(:default_concrete_class) do
    Class.new(Dependabot::PackageManagerBase) do
      def name
        "bundler"
      end

      def version
        Dependabot::Version.new("1.0.0")
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

  describe "#unsupported_versions" do
    it "returns an array of unsupported versions" do
      expect(package_manager.unsupported_versions).to eq([Dependabot::Version.new("0")])
    end

    it "returns an empty array by default" do
      expect(default_package_manager.unsupported_versions).to eq([])
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
  end

  describe "#deprecated?" do
    it "returns true if the current version is deprecated" do
      expect(package_manager.deprecated?).to be true
    end

    it "returns false if the current version is not deprecated" do
      allow(package_manager).to receive(:version).and_return(Dependabot::Version.new("1.1.0"))
      expect(package_manager.deprecated?).to be false
    end

    it "returns true if the current version is a major version and deprecated" do
      allow(package_manager).to receive(:version).and_return(Dependabot::Version.new("1"))
      expect(package_manager.deprecated?).to be true
    end
  end

  describe "#unsupported?" do
    it "returns true if the current version is unsupported" do
      allow(package_manager).to receive(:version).and_return(Dependabot::Version.new("0.9.0"))
      expect(package_manager.unsupported?).to be true
    end

    it "returns false if the current version is supported" do
      expect(package_manager.unsupported?).to be false
    end

    it "returns false if there is no list of supported versions" do
      allow(default_package_manager).to receive(:version).and_return(Dependabot::Version.new("1.0.0"))
      expect(default_package_manager.unsupported?).to be false
    end

    it "returns true if the current version is a major version and unsupported" do
      allow(package_manager).to receive(:version).and_return(Dependabot::Version.new("0"))
      expect(package_manager.unsupported?).to be true
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
