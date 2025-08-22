# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/version"

RSpec.describe Dependabot::Conda::Version do
  subject(:version) { described_class.new(version_string) }

  describe ".correct?" do
    it "accepts valid version strings" do
      expect(described_class.correct?("1.0.0")).to be(true)
      expect(described_class.correct?("1.0.0a1")).to be(true)
      expect(described_class.correct?("1.0.0.dev0")).to be(true)
      expect(described_class.correct?("2.0.0rc1")).to be(true)
      expect(described_class.correct?("1!1.0.0")).to be(true)
    end

    it "rejects invalid version strings" do
      expect(described_class.correct?("")).to be(false)
      expect(described_class.correct?(nil)).to be(false)
      expect(described_class.correct?("not.a.version")).to be(false)
    end
  end

  describe "#to_s" do
    context "with a standard version" do
      let(:version_string) { "1.2.3" }

      it { expect(version.to_s).to eq("1.2.3") }
    end

    context "with a prerelease version" do
      let(:version_string) { "1.2.3a1" }

      it { expect(version.to_s).to eq("1.2.3a1") }
    end

    context "with an epoch" do
      let(:version_string) { "1!1.2.3" }

      it { expect(version.to_s).to eq("1!1.2.3") }
    end
  end

  describe "comparisons" do
    it "correctly compares standard versions" do
      expect(described_class.new("1.0.0")).to be < described_class.new("1.0.1")
      expect(described_class.new("1.0.1")).to be > described_class.new("1.0.0")
    end

    it "correctly identifies equal versions" do
      version1 = described_class.new("1.0.0")
      version2 = described_class.new("1.0.0")
      expect(version1).to eq(version2)
      expect(version1).to eql(version2)
    end

    it "correctly compares prerelease versions" do
      expect(described_class.new("1.0.0a1")).to be < described_class.new("1.0.0")
      expect(described_class.new("1.0.0a1")).to be < described_class.new("1.0.0a2")
      expect(described_class.new("1.0.0rc1")).to be > described_class.new("1.0.0a1")
    end

    it "correctly handles epochs" do
      expect(described_class.new("1!1.0.0")).to be > described_class.new("2.0.0")
      expect(described_class.new("2!1.0.0")).to be > described_class.new("1!2.0.0")
    end
  end

  describe "#prerelease?" do
    it "identifies prerelease versions" do
      expect(described_class.new("1.0.0a1")).to be_prerelease
      expect(described_class.new("1.0.0b1")).to be_prerelease
      expect(described_class.new("1.0.0rc1")).to be_prerelease
      expect(described_class.new("1.0.0.dev0")).to be_prerelease
    end

    it "identifies stable versions" do
      expect(described_class.new("1.0.0")).not_to be_prerelease
      expect(described_class.new("1.2.3")).not_to be_prerelease
    end
  end
end
