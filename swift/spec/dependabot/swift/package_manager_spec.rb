# typed: false
# frozen_string_literal: true

require "dependabot/swift/package_manager"
require "dependabot/ecosystem"

RSpec.describe Dependabot::Swift::PackageManager do
  subject(:package_manager) { described_class.new(version) }

  let(:version) { "6.0.2" }

  describe "#version" do
    it "returns the version" do
      expect(package_manager.version.to_s).to eq version
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(package_manager.name).to eq(Dependabot::Swift::PACKAGE_MANAGER)
    end
  end

  describe "#deprecated_versions" do
    it "returns deprecated versions" do
      expect(package_manager.deprecated_versions).to eq(Dependabot::Swift::DEPRECATED_SWIFT_VERSIONS)
    end
  end

  describe "#supported_versions" do
    it "returns supported versions" do
      expect(package_manager.supported_versions).to eq(Dependabot::Swift::SUPPORTED_SWIFT_VERSIONS)
    end
  end
end
