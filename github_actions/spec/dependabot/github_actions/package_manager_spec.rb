# typed: false
# frozen_string_literal: true

require "dependabot/github_actions/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::GithubActions::PackageManager do
  let(:package_manager) { described_class.new }

  describe "#version_to_s" do
    it "returns the package manager version empty" do
      expect(package_manager.version_to_s).to eq("1.0.0")
    end
  end

  describe "#version_to_raw_s" do
    it "returns the package manager raw version empty" do
      expect(package_manager.version_to_raw_s).to eq("1.0.0")
    end
  end

  describe "#deprecated?" do
    it "returns always false" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    it "returns always false" do
      expect(package_manager.unsupported?).to be false
    end
  end
end
