# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/version"

RSpec.describe Dependabot::Julia::Version do
  subject(:version) { described_class.new(version_string) }

  describe ".correct?" do
    it "accepts plain semver versions" do
      expect(described_class.correct?("1.2.3")).to be true
      expect(described_class.correct?("0.5")).to be true
      expect(described_class.correct?("2")).to be true
    end

    it "accepts v-prefixed versions" do
      expect(described_class.correct?("v1.2.3")).to be true
    end

    it "accepts JLL build metadata" do
      expect(described_class.correct?("1.6.10+0")).to be true
      expect(described_class.correct?("2.28.6+4")).to be true
    end

    it "accepts prerelease versions" do
      expect(described_class.correct?("2.0.0-beta1")).to be true
      expect(described_class.correct?("1.0.0-rc.1+3")).to be true
    end

    it "rejects nil and malformed strings" do
      expect(described_class.correct?(nil)).to be false
      expect(described_class.correct?("not-a-version")).to be false
      expect(described_class.correct?("1..2")).to be false
    end
  end

  describe ".new" do
    it "parses JLL versions with build metadata without raising" do
      expect(described_class.new("1.6.10+0")).to be_a(described_class)
      expect(described_class.new("1.2.13+1")).to be_a(described_class)
    end

    it "strips the v prefix" do
      expect(described_class.new("v1.2.3")).to eq(described_class.new("1.2.3"))
    end
  end

  describe "#to_s" do
    it "round-trips build metadata" do
      expect(described_class.new("1.6.10+1").to_s).to eq("1.6.10+1")
    end

    it "round-trips plain versions" do
      expect(described_class.new("1.2.3").to_s).to eq("1.2.3")
    end
  end

  describe "ordering" do
    it "orders numeric builds of the same version" do
      expect(described_class.new("1.6.10+1")).to be > described_class.new("1.6.10+0")
      expect(described_class.new("1.6.10+10")).to be > described_class.new("1.6.10+9")
    end

    it "orders builds below the next patch version" do
      expect(described_class.new("1.6.10+5")).to be < described_class.new("1.6.11")
      expect(described_class.new("1.6.10+5")).to be > described_class.new("1.6.9")
    end

    it "orders prereleases below the release" do
      expect(described_class.new("2.0.0-beta1")).to be < described_class.new("2.0.0")
    end

    it "supports max over mixed version styles" do
      versions = %w(1.6.9 1.6.10+0 1.6.10+1 1.6.10).map { |v| described_class.new(v) }
      expect(versions.max.to_s).to eq("1.6.10+1")
    end
  end

  describe "#prerelease?" do
    it "is false for build-metadata-only versions" do
      expect(described_class.new("1.6.10+0")).not_to be_prerelease
    end

    it "is true for prerelease tags" do
      expect(described_class.new("2.0.0-beta1")).to be_prerelease
    end
  end
end
