# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/crystal_shards/requirement"
require "dependabot/crystal_shards/version"

RSpec.describe Dependabot::CrystalShards::Requirement do
  describe ".requirements_array" do
    subject(:requirements) { described_class.requirements_array(requirement_string) }

    context "with a simple requirement" do
      let(:requirement_string) { ">= 1.0.0" }

      it "returns an array with one requirement" do
        expect(requirements.length).to eq(1)
        expect(requirements.first).to be_a(described_class)
      end
    end

    context "with a nil requirement" do
      let(:requirement_string) { nil }

      it "returns an array with a permissive requirement" do
        expect(requirements.length).to eq(1)
        expect(requirements.first.satisfied_by?(Dependabot::CrystalShards::Version.new("1.0.0"))).to be true
      end
    end
  end

  describe "#initialize" do
    context "with comma-separated requirements" do
      subject(:requirement) { described_class.new(">= 1.0.0, < 2.0.0") }

      it "parses multiple requirements" do
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("1.5.0"))).to be true
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("0.9.0"))).to be false
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("2.0.0"))).to be false
      end
    end

    context "with a pessimistic operator" do
      subject(:requirement) { described_class.new("~> 1.0.0") }

      it "handles the pessimistic operator correctly" do
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("1.0.0"))).to be true
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("1.0.5"))).to be true
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("1.1.0"))).to be false
      end
    end
  end

  describe "#satisfied_by?" do
    subject(:requirement) { described_class.new(requirement_string) }

    context "with >= constraint" do
      let(:requirement_string) { ">= 1.0.0" }

      it "returns true for versions >= 1.0.0" do
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("1.0.0"))).to be true
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("2.0.0"))).to be true
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("0.9.0"))).to be false
      end
    end

    context "with exact version constraint" do
      let(:requirement_string) { "= 1.0.0" }

      it "returns true only for exact version" do
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("1.0.0"))).to be true
        expect(requirement.satisfied_by?(Dependabot::CrystalShards::Version.new("1.0.1"))).to be false
      end
    end
  end
end
