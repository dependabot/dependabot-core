# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/devbox/requirement"

RSpec.describe Dependabot::Devbox::Requirement do
  subject(:requirement) { described_class.new(constraint) }

  describe ".requirements_array" do
    it "parses a single constraint" do
      reqs = described_class.requirements_array("3.10")
      expect(reqs.length).to eq(1)
    end

    it "handles nil as an unrestricted requirement" do
      reqs = described_class.requirements_array(nil)
      expect(reqs.length).to eq(1)
      expect(reqs.first.satisfied_by?(Gem::Version.new("99.0.0"))).to be true
    end
  end

  describe "the latest sentinel" do
    let(:constraint) { "latest" }

    it "maps to an unrestricted requirement" do
      expect(requirement.constraints).to eq([">= 0"])
      expect(requirement.satisfied_by?(Gem::Version.new("99.99.99"))).to be true
    end
  end

  describe "a pinned major constraint" do
    let(:constraint) { "3" }

    it "maps to the major version line" do
      expect(requirement.constraints).to eq(["~> 3.0"])
    end

    it "allows minor and patch bumps within the line" do
      expect(requirement.satisfied_by?(Gem::Version.new("3.10.19"))).to be true
      expect(requirement.satisfied_by?(Gem::Version.new("3.99.0"))).to be true
    end

    it "disallows the next major" do
      expect(requirement.satisfied_by?(Gem::Version.new("4.0.0"))).to be false
    end
  end

  describe "a pinned minor constraint" do
    let(:constraint) { "3.10" }

    it "maps to the minor version line" do
      expect(requirement.constraints).to eq(["~> 3.10.0"])
    end

    it "allows patch bumps within the line" do
      expect(requirement.satisfied_by?(Gem::Version.new("3.10.19"))).to be true
    end

    it "disallows the next minor" do
      expect(requirement.satisfied_by?(Gem::Version.new("3.11.0"))).to be false
    end
  end

  describe "a pinned exact constraint" do
    let(:constraint) { "3.10.19" }

    it "maps to an exact match" do
      expect(requirement.constraints).to eq(["= 3.10.19"])
    end

    it "matches the exact version" do
      expect(requirement.satisfied_by?(Gem::Version.new("3.10.19"))).to be true
    end

    it "rejects any other version" do
      expect(requirement.satisfied_by?(Gem::Version.new("3.10.20"))).to be false
    end
  end
end
