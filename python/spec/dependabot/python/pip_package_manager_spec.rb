# typed: false
# frozen_string_literal: true

require "dependabot/python/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Python::PipPackageManager do
  let(:package_manager) { described_class.new("24.0") }

  describe "#initialize" do
    context "when version is a String" do
      it "sets the version correctly" do
        expect(package_manager.version).to eq("24.0")
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq("pip")
      end
    end

    context "when version is a malformed string" do
      let(:package_manager) { described_class.new("1.8.3)") }

      it "raises error" do
        expect { package_manager.version }.to raise_error(Dependabot::BadRequirementError)
      end
    end
  end
end
