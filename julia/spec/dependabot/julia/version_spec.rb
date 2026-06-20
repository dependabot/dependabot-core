# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/version"

RSpec.describe Dependabot::Julia::Version do
  describe ".correct?" do
    it "returns true for plain versions" do
      expect(described_class.correct?("1.2.3")).to be true
      expect(described_class.correct?("0.0.43")).to be true
    end

    it "returns true for versions with a 'v' prefix" do
      expect(described_class.correct?("v1.2.3")).to be true
    end

    it "returns true for versions with build metadata" do
      expect(described_class.correct?("0.0.43+0")).to be true
      expect(described_class.correct?("0.0.43+1")).to be true
    end

    it "returns false for non-versions" do
      expect(described_class.correct?("not-a-version")).to be false
    end

    it "returns false for nil" do
      expect(described_class.correct?(nil)).to be false
    end
  end

  describe "#initialize" do
    it "accepts a plain version" do
      expect(described_class.new("1.2.3").to_s).to eq("1.2.3")
    end

    it "strips a leading 'v' prefix" do
      expect(described_class.new("v1.2.3").to_s).to eq("1.2.3")
    end

    it "strips JLL build metadata" do
      # Julia's JLL packages use the "+N" suffix to identify rebuilds of the
      # same source version. Per semver, build metadata is ignored when ordering,
      # and Julia's Pkg treats e.g. "0.0.43" and "0.0.43+1" as equivalent for
      # compatibility purposes.
      expect(described_class.new("0.0.43+0").to_s).to eq("0.0.43")
      expect(described_class.new("0.0.43+1").to_s).to eq("0.0.43")
      expect(described_class.new("1.2.3+build.5").to_s).to eq("1.2.3")
    end

    it "strips both 'v' prefix and build metadata" do
      expect(described_class.new("v0.0.43+1").to_s).to eq("0.0.43")
    end
  end

  describe "ordering" do
    it "treats build metadata as equivalent to the source version" do
      # Versions differing only in build metadata must compare equal so that
      # a JLL rebuild (e.g. 0.0.43+1) does not appear as a newer release than
      # the source version (0.0.43) it was rebuilt from.
      expect(described_class.new("0.0.43+1") <=> described_class.new("0.0.43")).to eq(0)
      expect(described_class.new("0.0.43+1") <=> described_class.new("0.0.43+0")).to eq(0)
      expect(described_class.new("0.0.43+1")).to eq(described_class.new("0.0.43"))
    end

    it "compares plain versions" do
      expect(described_class.new("1.2.3") < described_class.new("1.2.4")).to be true
      expect(described_class.new("2.0.0") > described_class.new("1.99.99")).to be true
    end
  end

  describe "satisfying requirements" do
    it "considers a build-metadata version satisfied by an exact pin on the source version" do
      # Regression: previously "=0.0.43" would not be satisfied by "0.0.43+1",
      # causing Dependabot to propose a redundant relaxation when JLL packages
      # published a rebuild (e.g. 0.0.43+1) of an exactly-pinned version.
      req = Gem::Requirement.new("=0.0.43")
      expect(req.satisfied_by?(described_class.new("0.0.43+1"))).to be true
      expect(req.satisfied_by?(described_class.new("0.0.43+0"))).to be true
    end
  end
end
