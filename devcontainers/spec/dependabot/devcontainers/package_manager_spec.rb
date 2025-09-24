# typed: false
# frozen_string_literal: true

require "dependabot/devcontainers/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Devcontainers::PackageManager do
  subject(:package_manager) { described_class.new(version) }

  let(:version) { "2.1.1" }

  describe "#version" do
    it "returns the version" do
      expect(package_manager.version.to_s).to eq version
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(package_manager.name).to eq(Dependabot::Devcontainers::PACKAGE_MANAGER)
    end
  end

  describe "#deprecated_versions" do
    it "returns deprecated versions" do
      expect(package_manager.deprecated_versions).to eq(Dependabot::Devcontainers::DEPRECATED_DEVCONTAINER_VERSIONS)
    end
  end

  describe "#supported_versions" do
    it "returns supported versions" do
      expect(package_manager.supported_versions).to eq(Dependabot::Devcontainers::SUPPORTED_DEVCONTAINER_VERSIONS)
    end
  end
end
