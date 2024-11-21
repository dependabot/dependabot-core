# typed: false
# frozen_string_literal: true

require "dependabot/python/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Python::PackageManager do
  let(:package_manager) { described_class.new(version, requirement) }
  let(:requirement) { nil }

  describe "#initialize" do
    context "when version is a String" do
      let(:version) { "3.11.2" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(Dependabot::Python::Version.new(version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::Python::PACKAGE_MANAGER)
      end
    end

    context "when version is a Dependabot::Python::Version" do
      let(:version) { "2" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(version)
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::Python::PACKAGE_MANAGER)
      end
    end

    context "when a requirement is provided" do
      let(:version) { "2.1" }
      let(:requirement) { Dependabot::Python::Requirement.new(">= 1.12.0, ~> 2.3.0") }

      it "sets the requirement correctly" do
        expect(package_manager.requirement.to_s).to eq(">= 1.12.0, ~> 2.3.0")
      end

      it "calculates the correct min_version" do
        expect(package_manager.requirement.min_version).to eq(Dependabot::Version.new("2.3.0"))
      end

      it "calculates the correct max_version" do
        expect(package_manager.requirement.max_version).to eq(Dependabot::Version.new("2.4.0"))
      end
    end

    context "when a single minimum constraint is provided" do
      let(:version) { "2.1" }
      let(:requirement) { Dependabot::Python::Requirement.new(">= 1.5") }

      it "sets the requirement correctly" do
        expect(package_manager.requirement.to_s).to eq(">= 1.5")
      end

      it "calculates the correct min_version" do
        expect(package_manager.requirement.min_version).to eq(Dependabot::Version.new("1.5"))
      end

      it "returns nil for max_version" do
        expect(package_manager.requirement.max_version).to be_nil
      end
    end
  end

  describe "#raise_if_unsupported!" do
    context "when version is supported" do
      let(:version) { "2.1" }

      it "does not raise an error" do
        expect { package_manager.raise_if_unsupported! }.not_to raise_error
      end
    end
  end
end
