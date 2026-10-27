# typed: strict
# frozen_string_literal: true

require "dependabot/opentofu/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Opentofu::PackageManager do
  extend T::Sig

  sig { returns(Dependabot::Opentofu::PackageManager) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:package_manager) { described_class.new(version) }

  sig { returns(String) }
  let(:version) { "2.1.1" }

  describe "#version" do
    it "returns the version" do
      expect(package_manager.version.to_s).to eq version
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(package_manager.name).to eq(Dependabot::Opentofu::PACKAGE_MANAGER)
    end
  end

  describe "#deprecated_versions" do
    it "returns deprecated versions" do
      expect(package_manager.deprecated_versions).to eq(Dependabot::Opentofu::DEPRECATED_OPENTOFU_VERSIONS)
    end
  end

  describe "#supported_versions" do
    it "returns supported versions" do
      expect(package_manager.supported_versions).to eq(Dependabot::Opentofu::SUPPORTED_OPENTOFU_VERSIONS)
    end
  end
end
