# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/nixpkgs_version"

RSpec.describe Dependabot::Nix::NixpkgsVersion do
  describe ".valid?" do
    it "accepts standard nixos release branches" do
      expect(described_class.valid?("nixos-22.05")).to be true
      expect(described_class.valid?("nixos-23.11")).to be true
      expect(described_class.valid?("nixos-24.05")).to be true
    end

    it "accepts nixpkgs and release prefixes" do
      expect(described_class.valid?("nixpkgs-22.05")).to be true
      expect(described_class.valid?("release-23.11")).to be true
    end

    it "accepts unstable variants" do
      expect(described_class.valid?("nixos-unstable")).to be true
      expect(described_class.valid?("nixpkgs-unstable")).to be true
    end

    it "accepts suffix variants" do
      expect(described_class.valid?("nixos-22.05-small")).to be true
      expect(described_class.valid?("nixos-22.05-aarch64")).to be true
      expect(described_class.valid?("nixpkgs-22.05-darwin")).to be true
      expect(described_class.valid?("nixos-unstable-small")).to be true
    end

    it "rejects invalid branch names" do
      expect(described_class.valid?("main")).to be false
      expect(described_class.valid?("master")).to be false
      expect(described_class.valid?("22.05")).to be false
      expect(described_class.valid?("1.2.3")).to be false
      expect(described_class.valid?("unknown-22.05")).to be false
      expect(described_class.valid?("nixos-22.05-aarch64-small")).to be false
      expect(described_class.valid?("nixos-22.05-unknown")).to be false
      expect(described_class.valid?("")).to be false
    end
  end

  describe "#initialize" do
    it "parses a numbered release" do
      v = described_class.new("nixos-23.11")
      expect(v.prefix).to eq("nixos")
      expect(v.release).to eq([23, 11])
      expect(v.suffix).to be_nil
      expect(v.branch).to eq("nixos-23.11")
    end

    it "parses an unstable branch" do
      v = described_class.new("nixos-unstable")
      expect(v.prefix).to eq("nixos")
      expect(v.release).to be_nil
      expect(v.suffix).to be_nil
    end

    it "parses a branch with suffix" do
      v = described_class.new("nixos-22.05-small")
      expect(v.prefix).to eq("nixos")
      expect(v.release).to eq([22, 5])
      expect(v.suffix).to eq("small")
    end

    it "raises on invalid branch" do
      expect { described_class.new("main") }.to raise_error(ArgumentError, /Invalid nixpkgs branch/)
    end
  end

  describe "#unstable? / #stable?" do
    it "identifies unstable branches" do
      expect(described_class.new("nixos-unstable")).to be_unstable
      expect(described_class.new("nixos-unstable-small")).to be_unstable
      expect(described_class.new("nixpkgs-unstable")).to be_unstable
    end

    it "identifies stable branches" do
      expect(described_class.new("nixos-23.11")).to be_stable
      expect(described_class.new("nixpkgs-22.05-darwin")).to be_stable
    end
  end

  describe "#compatibility / #compatible_with?" do
    it "computes compatibility from prefix alone when no suffix" do
      expect(described_class.new("nixos-22.05").compatibility).to eq("nixos")
      expect(described_class.new("nixos-23.11").compatibility).to eq("nixos")
      expect(described_class.new("nixos-unstable").compatibility).to eq("nixos")
    end

    it "includes suffix in compatibility" do
      expect(described_class.new("nixos-22.05-small").compatibility).to eq("nixos-small")
      expect(described_class.new("nixos-unstable-small").compatibility).to eq("nixos-small")
    end

    it "considers same-prefix versions compatible" do
      v1 = described_class.new("nixos-22.05")
      v2 = described_class.new("nixos-23.11")
      v3 = described_class.new("nixos-unstable")
      expect(v1.compatible_with?(v2)).to be true
      expect(v1.compatible_with?(v3)).to be true
    end

    it "considers different prefixes incompatible" do
      v1 = described_class.new("nixos-22.05")
      v2 = described_class.new("nixpkgs-22.05")
      expect(v1.compatible_with?(v2)).to be false
    end

    it "considers different suffixes incompatible" do
      v1 = described_class.new("nixos-22.05")
      v2 = described_class.new("nixos-22.05-small")
      expect(v1.compatible_with?(v2)).to be false
    end
  end

  describe "#<=>" do
    it "orders numbered releases by [major, minor]" do
      v1 = described_class.new("nixos-22.05")
      v2 = described_class.new("nixos-23.11")
      v3 = described_class.new("nixos-23.05")

      expect(v2).to be > v1
      expect(v2).to be > v3
      expect(v3).to be > v1
    end

    it "considers unstable greater than any numbered release" do
      unstable = described_class.new("nixos-unstable")
      numbered = described_class.new("nixos-99.99")
      expect(unstable).to be > numbered
    end

    it "considers two unstable versions equal" do
      v1 = described_class.new("nixos-unstable")
      v2 = described_class.new("nixos-unstable")
      expect(v1 <=> v2).to eq(0)
    end

    it "returns nil for incomparable types" do
      v = described_class.new("nixos-23.11")
      expect(v <=> "not a version").to be_nil
    end
  end

  describe "#to_s" do
    it "returns the original branch name" do
      expect(described_class.new("nixos-23.11").to_s).to eq("nixos-23.11")
      expect(described_class.new("nixos-unstable-small").to_s).to eq("nixos-unstable-small")
    end
  end

  describe "sorting" do
    it "sorts a list of versions correctly" do
      versions = %w(
        nixos-21.11
        nixos-23.11
        nixos-22.05
        nixos-23.05
      ).map { |b| described_class.new(b) }

      sorted = versions.sort.map(&:to_s)
      expect(sorted).to eq(%w(nixos-21.11 nixos-22.05 nixos-23.05 nixos-23.11))
    end
  end
end
