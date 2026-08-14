# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/versioned_name"

RSpec.describe Dependabot::Nix::VersionedName do
  describe "#versioned?" do
    it "is true for a YY.MM name" do
      expect(described_class.new("nixos-26.05").versioned?).to be(true)
    end

    it "is true for a suffixed name" do
      expect(described_class.new("nixpkgs-26.05-darwin").versioned?).to be(true)
    end

    it "is false for a rolling name" do
      expect(described_class.new("nixos-unstable").versioned?).to be(false)
    end

    it "is false for a semver-like tag" do
      expect(described_class.new("v0.5").versioned?).to be(false)
    end
  end

  describe "#prefix, #suffix, #version_string" do
    it "splits a plain versioned name" do
      name = described_class.new("nixos-26.05")
      expect(name.prefix).to eq("nixos-")
      expect(name.suffix).to be_nil
      expect(name.version_string).to eq("26.05")
    end

    it "captures the suffix" do
      name = described_class.new("nixos-24.11-small")
      expect(name.prefix).to eq("nixos-")
      expect(name.suffix).to eq("-small")
      expect(name.version_string).to eq("24.11")
    end

    it "returns nil parts for a rolling name" do
      name = described_class.new("nixos-unstable")
      expect(name.prefix).to be_nil
      expect(name.suffix).to be_nil
      expect(name.version_string).to be_nil
    end
  end

  describe "#version" do
    it "parses YY.MM into [year, month]" do
      expect(described_class.new("nixos-26.05").version).to eq([26, 5])
    end

    it "rejects an invalid month" do
      expect(described_class.new("nixos-26.13").version).to be_nil
    end

    it "returns nil for a rolling name" do
      expect(described_class.new("nixos-unstable").version).to be_nil
    end
  end

  describe "#same_family?" do
    let(:current) { described_class.new("nixos-25.05") }

    it "matches the same prefix and suffix" do
      expect(described_class.new("nixos-26.05").same_family?(current)).to be(true)
    end

    it "rejects a different suffix" do
      expect(described_class.new("nixos-26.05-small").same_family?(current)).to be(false)
    end

    it "rejects a different prefix" do
      expect(described_class.new("release-26.05").same_family?(current)).to be(false)
    end

    it "rejects a rolling name" do
      expect(described_class.new("nixos-unstable").same_family?(current)).to be(false)
    end
  end

  describe "#newer_than?" do
    let(:current) { described_class.new("nixos-25.05") }

    it "is true for a later version in the same year" do
      expect(described_class.new("nixos-25.11").newer_than?(current)).to be(true)
    end

    it "is true across a year boundary" do
      expect(described_class.new("nixos-26.05").newer_than?(described_class.new("nixos-25.11"))).to be(true)
    end

    it "is false for an equal version" do
      expect(described_class.new("nixos-25.05").newer_than?(current)).to be(false)
    end

    it "is false for an earlier version" do
      expect(described_class.new("nixos-24.11").newer_than?(current)).to be(false)
    end
  end
end
