# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/version"

RSpec.describe Dependabot::PreCommit::Version do
  describe ".correct?" do
    it "accepts versions without a v prefix" do
      expect(described_class.correct?("0.13.5")).to be(true)
    end

    it "accepts versions with a v prefix" do
      expect(described_class.correct?("v0.17.2")).to be(true)
      expect(described_class.correct?("V1.9.4")).to be(true)
    end

    it "rejects nil and empty values" do
      expect(described_class.correct?(nil)).to be(false)
      expect(described_class.correct?("")).to be(false)
    end

    it "rejects non-version refs" do
      expect(described_class.correct?("v")).to be(false)
      expect(described_class.correct?("vfoo")).to be(false)
      expect(described_class.correct?("main")).to be(false)
      expect(described_class.correct?("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2")).to be(false)
    end
  end

  describe ".new" do
    it "strips a leading v" do
      expect(described_class.new("v0.17.2").to_s).to eq("0.17.2")
    end

    it "treats v-prefixed and plain versions as equal" do
      expect(described_class.new("v1.9.4")).to eq(described_class.new("1.9.4"))
    end

    it "compares v-prefixed versions with plain versions" do
      expect(described_class.new("v0.17.2")).to be < described_class.new("0.17.4")
    end

    it "computes semver parts for v-prefixed versions" do
      expect(described_class.new("v1.31.1").semver_parts).to eq([1, 31, 1])
    end
  end
end
