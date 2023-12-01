# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/version"

RSpec.describe Dependabot::Docker::Version do
  describe ".correct?" do
    it "returns true for versions" do
      expect(described_class.correct?("3.7.7-slim-buster")).to be true
      expect(described_class.correct?("20.9.0-alpine3.18")).to be true
    end

    it "returns true for versions with prefixes" do
      expect(described_class.correct?("img_20230915.3")).to be true
      expect(described_class.correct?("artful-20170826")).to be true
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

    it "sorts properly for <prefix>_<version>" do
      expect(described_class.new("artful_10")).to be < described_class.new("artful_15")
    end

    it "sorts properly for <prefix>-<version>" do
      expect(described_class.new("artful-10")).to be < described_class.new("artful-15")
    end

    it "sorts properly for <prefix>_<year><month><day>.<version>" do
      expect(described_class.new("img_20230915.3")).to be < described_class.new("img_20231011.1")
    end
  end

  describe ".correct?" do
    def check_version_for_correctness?(version)
      docker_version = described_class.new(version)
      described_class.correct?(docker_version)
    end

    it "classifies standard versions as correct" do
      expect(check_version_for_correctness?("2.4.2")).to be true
      expect(check_version_for_correctness?("20.9.0.alpine3.18")).to be true
      expect(check_version_for_correctness?("20.9.0-alpine3.18")).to be true
      expect(check_version_for_correctness?("3.7.7-slim-buster")).to be true
    end

    it "classifies java versions as correct" do
      expect(check_version_for_correctness?("11.0.16_8")).to be true
      expect(check_version_for_correctness?("v11.0.16_8")).to be true
      expect(check_version_for_correctness?("11.0.16.1")).to be true
    end

    it "classifies <prefix>_<year><month><day>.<version> versions as correct" do
      expect(check_version_for_correctness?("img_20230915.3")).to be true
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

    it "classifies prefixed versions as correct" do
      expect(described_class.new("img_20230915.3").to_semver).to eq("20230915.3")
      expect(described_class.new("artful-20170826").to_semver).to eq("20170826")
      expect(described_class.new("artful.20170826").to_semver).to eq("20170826")
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
