# typed: false
# frozen_string_literal: true

require "dependabot/terraform/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Terraform::PackageManager do
  subject(:package_manager) { described_class.new(version) }

  let(:version) { "2.1.1" }

  describe "#version" do
    it "returns the version" do
      expect(package_manager.version.to_s).to eq version
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(package_manager.name).to eq(Dependabot::Terraform::PACKAGE_MANAGER)
    end
  end

  describe "#deprecated_versions" do
    it "returns deprecated versions" do
      expect(package_manager.deprecated_versions).to eq(Dependabot::Terraform::DEPRECATED_TERRAFORM_VERSIONS)
    end
  end

  describe "#supported_versions" do
    it "returns supported versions" do
      expect(package_manager.supported_versions).to eq(Dependabot::Terraform::SUPPORTED_TERRAFORM_VERSIONS)
    end
  end
end
