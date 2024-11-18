# typed: false
# frozen_string_literal: true

require "dependabot/maven/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Maven::PackageManager do
  subject(:package_manager) { described_class.new(version) }

  let(:version) { "3.9.5" }

  describe "#version" do
    it "returns the version" do
      expect(package_manager.version).to eq(Dependabot::Maven::Version.new(version))
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(package_manager.name).to eq(Dependabot::Maven::PACKAGE_MANAGER)
    end
  end

  describe "#deprecated_versions" do
    it "returns deprecated versions" do
      expect(package_manager.deprecated_versions).to eq(Dependabot::Maven::DEPRECATED_MAVEN_VERSIONS)
    end
  end

  describe "#supported_versions" do
    it "returns supported versions" do
      expect(package_manager.supported_versions).to eq(Dependabot::Maven::SUPPORTED_MAVEN_VERSIONS)
    end
  end
end
