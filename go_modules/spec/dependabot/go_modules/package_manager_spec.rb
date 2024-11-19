# typed: false
# frozen_string_literal: true

require "dependabot/go_modules/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::GoModules::PackageManager do
  subject(:package_manager) { described_class.new(version) }

  let(:version) { "1.12" }

  describe "#version" do
    it "returns the version" do
      expect(package_manager.version).to eq(Dependabot::GoModules::Version.new(version))
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(package_manager.name).to eq(Dependabot::GoModules::PACKAGE_MANAGER)
    end
  end

  describe "#deprecated_versions" do
    it "returns deprecated versions" do
      expect(package_manager.deprecated_versions).to eq(Dependabot::GoModules::DEPRECATED_GO_VERSIONS)
    end
  end

  describe "#supported_versions" do
    it "returns supported versions" do
      expect(package_manager.supported_versions).to eq(Dependabot::GoModules::SUPPORTED_GO_VERSIONS)
    end
  end
end
