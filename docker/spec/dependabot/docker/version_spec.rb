# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/version"

RSpec.describe Dependabot::Docker::Version do
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
end
