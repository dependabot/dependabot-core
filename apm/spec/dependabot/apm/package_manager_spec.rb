# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/ecosystem"
require "dependabot/apm/package_manager"

RSpec.describe Dependabot::Apm::PackageManager do
  subject(:package_manager) { described_class.new(version) }

  let(:version) { "0.4.2" }

  describe "#version" do
    it "returns the version" do
      expect(package_manager.version.to_s).to eq(version)
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(package_manager.name).to eq(Dependabot::Apm::PACKAGE_MANAGER)
    end
  end

  describe "#deprecated_versions" do
    it "returns deprecated versions" do
      expect(package_manager.deprecated_versions).to eq(Dependabot::Apm::DEPRECATED_APM_VERSIONS)
    end
  end

  describe "#supported_versions" do
    it "returns supported versions" do
      expect(package_manager.supported_versions).to eq(Dependabot::Apm::SUPPORTED_APM_VERSIONS)
    end
  end

  describe "#deprecated?" do
    it "is not deprecated" do
      expect(package_manager.deprecated?).to be(false)
    end
  end

  describe "#unsupported?" do
    it "is not unsupported" do
      expect(package_manager.unsupported?).to be(false)
    end
  end
end
