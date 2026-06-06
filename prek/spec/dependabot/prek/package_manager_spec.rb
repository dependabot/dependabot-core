# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/prek/package_manager"

RSpec.describe Dependabot::Prek::PackageManager do
  subject(:package_manager) { described_class.new }

  describe "#name" do
    it "is prek" do
      expect(package_manager.name).to eq("prek")
    end
  end

  describe "#version" do
    it "exposes a Dependabot version" do
      expect(package_manager.version).to be_a(Dependabot::Prek::Version)
    end
  end
end
