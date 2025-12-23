# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/lean/requirement"
require "dependabot/lean/version"

RSpec.describe Dependabot::Lean::Requirement do
  describe ".requirements_array" do
    it "returns an array of Requirement objects" do
      result = described_class.requirements_array("4.26.0")
      expect(result.length).to eq(1)
      expect(result.first).to be_a(described_class)
      expect(result.first.to_s).to eq("= 4.26.0")
    end

    it "returns empty array for nil or empty string" do
      expect(described_class.requirements_array(nil)).to eq([])
      expect(described_class.requirements_array("")).to eq([])
    end
  end

  describe "#satisfied_by?" do
    context "with exact version requirement" do
      let(:requirement) { described_class.new("= 4.26.0") }

      it "returns true for the exact version" do
        expect(requirement.satisfied_by?(Dependabot::Lean::Version.new("4.26.0"))).to be true
      end

      it "returns false for different versions" do
        expect(requirement.satisfied_by?(Dependabot::Lean::Version.new("4.25.0"))).to be false
        expect(requirement.satisfied_by?(Dependabot::Lean::Version.new("4.27.0"))).to be false
      end
    end

    context "with version range requirement" do
      let(:requirement) { described_class.new(">= 4.26.0") }

      it "returns true for versions that satisfy the requirement" do
        expect(requirement.satisfied_by?(Dependabot::Lean::Version.new("4.26.0"))).to be true
        expect(requirement.satisfied_by?(Dependabot::Lean::Version.new("4.27.0"))).to be true
        expect(requirement.satisfied_by?(Dependabot::Lean::Version.new("5.0.0"))).to be true
      end

      it "returns false for versions that don't satisfy the requirement" do
        expect(requirement.satisfied_by?(Dependabot::Lean::Version.new("4.25.0"))).to be false
      end
    end
  end
end
