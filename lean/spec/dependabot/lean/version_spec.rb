# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/lean/version"

RSpec.describe Dependabot::Lean::Version do
  describe ".correct?" do
    it "returns true for valid versions" do
      expect(described_class.correct?("4.26.0")).to be true
      expect(described_class.correct?("4.27.0-rc1")).to be true
      expect(described_class.correct?("4.27.0-rc2")).to be true
      expect(described_class.correct?("v4.26.0")).to be true
      expect(described_class.correct?("v4.27.0-rc1")).to be true
    end

    it "returns false for invalid versions" do
      expect(described_class.correct?("")).to be false
      expect(described_class.correct?("invalid")).to be false
      expect(described_class.correct?("4.26")).to be false
      expect(described_class.correct?("4.26.0-beta1")).to be false
      expect(described_class.correct?(nil)).to be false
    end
  end

  describe "#initialize" do
    it "parses stable versions correctly" do
      version = described_class.new("4.26.0")
      expect(version.major).to eq(4)
      expect(version.minor).to eq(26)
      expect(version.patch).to eq(0)
      expect(version.rc).to be_nil
      expect(version.to_s).to eq("4.26.0")
    end

    it "parses RC versions correctly" do
      version = described_class.new("4.27.0-rc2")
      expect(version.major).to eq(4)
      expect(version.minor).to eq(27)
      expect(version.patch).to eq(0)
      expect(version.rc).to eq(2)
      expect(version.to_s).to eq("4.27.0-rc2")
    end

    it "strips leading v" do
      version = described_class.new("v4.26.0")
      expect(version.to_s).to eq("4.26.0")
    end
  end

  describe "#prerelease?" do
    it "returns false for stable versions" do
      expect(described_class.new("4.26.0").prerelease?).to be false
    end

    it "returns true for RC versions" do
      expect(described_class.new("4.27.0-rc1").prerelease?).to be true
      expect(described_class.new("4.27.0-rc2").prerelease?).to be true
    end
  end

  describe "#<=>" do
    it "compares stable versions correctly" do
      expect(described_class.new("4.27.0")).to be > described_class.new("4.26.0")
      expect(described_class.new("4.26.1")).to be > described_class.new("4.26.0")
      expect(described_class.new("5.0.0")).to be > described_class.new("4.99.99")
    end

    it "compares RC versions correctly" do
      expect(described_class.new("4.27.0-rc2")).to be > described_class.new("4.27.0-rc1")
      expect(described_class.new("4.27.0-rc10")).to be > described_class.new("4.27.0-rc2")
    end

    it "ranks stable versions higher than RC versions of same base" do
      expect(described_class.new("4.27.0")).to be > described_class.new("4.27.0-rc2")
      expect(described_class.new("4.27.0")).to be > described_class.new("4.27.0-rc99")
    end

    it "ranks RC of newer version higher than stable of older version" do
      expect(described_class.new("4.27.0-rc1")).to be > described_class.new("4.26.0")
    end

    it "handles equality correctly" do
      version1 = described_class.new("4.26.0")
      version2 = described_class.new("4.26.0")
      expect(version1).to eq version2

      rc_version1 = described_class.new("4.27.0-rc1")
      rc_version2 = described_class.new("4.27.0-rc1")
      expect(rc_version1).to eq rc_version2
    end
  end
end
