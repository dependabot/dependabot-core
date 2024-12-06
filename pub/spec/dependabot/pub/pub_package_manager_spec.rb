# typed: false
# frozen_string_literal: true

require "dependabot/python/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Pub::PubPackageManager do
  let(:package_manager) { described_class.new("3.5.0") }

  describe "#initialize" do
    context "when version is a String" do
      it "sets the version correctly" do
        expect(package_manager.version).to eq("3.5.0")
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq("pub")
      end
    end
  end
end
