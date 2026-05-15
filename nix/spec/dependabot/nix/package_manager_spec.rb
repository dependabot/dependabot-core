# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/package_manager"

RSpec.describe Dependabot::Nix::PackageManager do
  subject(:package_manager) { described_class.new("2.28.3") }

  describe "#name" do
    it "returns nix" do
      expect(package_manager.name).to eq("nix")
    end
  end

  describe "#version" do
    it "returns the parsed version" do
      expect(package_manager.version.to_s).to eq("2.28.3")
    end
  end

  describe "#deprecated?" do
    it "returns false" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    it "returns false" do
      expect(package_manager.unsupported?).to be false
    end
  end
end
