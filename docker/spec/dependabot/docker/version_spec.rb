# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/version"

RSpec.describe Dependabot::Docker::Version do
  describe ".correct?" do
    it "returns true for versions" do
      expect(described_class.correct?("3.7.7-slim-buster")).to be true
    end

    it "returns false for non-versions" do
      expect(described_class.correct?("python")).to be false
    end
  end

  describe ".new" do
    it "sorts properly" do
      expect(described_class.new("2.4.2")).to be >= described_class.new("2.1.0")
      expect(described_class.new("2.4.2")).to be < described_class.new("2.4.3")
    end

    it "sorts properly when it uses underscores" do
      expect(described_class.new("11.0.16_8")).to be < described_class.new("11.0.16.1")
      expect(described_class.new("17.0.2_8")).to be > described_class.new("17.0.1_12")
    end
  end

  describe ".correct?" do
    it "classifies standard versions as correct" do
      expect(described_class.correct?("2.4.2")).to be true
    end

    it "classifies java versions as correct" do
      expect(described_class.correct?("11.0.16_8")).to be true
      expect(described_class.correct?("11.0.16.1")).to be true
    end
  end

  describe "#to_semver" do
    it "returns a semver compatible string for standard versions" do
      expect(described_class.new("2.4.2").to_semver).to eq("2.4.2")
    end

    it "classifies java versions as correct" do
      expect(described_class.new("11.0.16_8").to_semver).to eq("11.0.16")
      expect(described_class.new("11.0.16.1").to_semver).to eq("11.0.16.1")
    end
  end

  describe "#segments" do
    it "returns segments for standard versions" do
      expect(described_class.new("2.4.2").segments).to eq([2, 4, 2])
    end

    it "ignores java versions" do
      expect(described_class.new("11.0.16_8").segments).to eq([11, 0, 16])
    end
  end
end
