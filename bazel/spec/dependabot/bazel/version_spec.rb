# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/version"

RSpec.describe Dependabot::Bazel::Version do
  subject(:version) { described_class.new(version_string) }

  describe "#to_s" do
    context "with a standard semantic version" do
      let(:version_string) { "1.2.3" }

      it "returns the original version string" do
        expect(version.to_s).to eq("1.2.3")
      end
    end

    context "with a pre-release version using hyphen" do
      let(:version_string) { "1.7.0-rc4" }

      it "preserves the hyphen format (not Gem::Version's .pre. format)" do
        expect(version.to_s).to eq("1.7.0-rc4")
      end

      it "does not transform to .pre.rc format" do
        expect(version.to_s).not_to eq("1.7.0.pre.rc4")
      end
    end

    context "with a pre-release version using alpha" do
      let(:version_string) { "2.0.0-alpha.1" }

      it "preserves the original format" do
        expect(version.to_s).to eq("2.0.0-alpha.1")
      end
    end

    context "with a pre-release version using beta" do
      let(:version_string) { "3.1.0-beta.2" }

      it "preserves the original format" do
        expect(version.to_s).to eq("3.1.0-beta.2")
      end
    end
  end

  describe "#to_semver" do
    context "with a pre-release version" do
      let(:version_string) { "1.7.0-rc4" }

      it "returns the original version string" do
        expect(version.to_semver).to eq("1.7.0-rc4")
      end
    end
  end

  describe "version comparison" do
    it "correctly compares pre-release versions" do
      v1 = described_class.new("1.7.0-rc3")
      v2 = described_class.new("1.7.0-rc4")
      v3 = described_class.new("1.7.0")

      expect(v1).to be < v2
      expect(v2).to be < v3
    end

    it "correctly compares versions with different pre-release identifiers" do
      alpha = described_class.new("2.0.0-alpha.1")
      beta = described_class.new("2.0.0-beta.1")
      rc = described_class.new("2.0.0-rc.1")
      release = described_class.new("2.0.0")

      expect(alpha).to be < beta
      expect(beta).to be < rc
      expect(rc).to be < release
    end
  end

  describe "BCR .bcr.X suffix handling" do
    describe "#initialize" do
      context "with a .bcr.X suffix" do
        let(:version_string) { "1.6.50.bcr.1" }

        it "parses and stores the bcr suffix" do
          expect(version.bcr_suffix).to eq(1)
        end

        it "preserves the original version string" do
          expect(version.to_s).to eq("1.6.50.bcr.1")
        end
      end

      context "with a higher .bcr.X suffix" do
        let(:version_string) { "1.6.50.bcr.10" }

        it "parses multi-digit bcr suffixes" do
          expect(version.bcr_suffix).to eq(10)
        end
      end

      context "without a .bcr.X suffix" do
        let(:version_string) { "1.6.50" }

        it "has nil bcr_suffix" do
          expect(version.bcr_suffix).to be_nil
        end
      end
    end

    describe "version comparison with .bcr.X suffixes" do
      it "treats .bcr.X versions as newer than base version" do
        base = described_class.new("1.6.50")
        bcr1 = described_class.new("1.6.50.bcr.1")

        expect(bcr1).to be > base
        expect(base).to be < bcr1
      end

      it "correctly orders multiple .bcr.X versions" do
        base = described_class.new("1.6.50")
        bcr1 = described_class.new("1.6.50.bcr.1")
        bcr2 = described_class.new("1.6.50.bcr.2")

        expect(bcr2).to be > bcr1
        expect(bcr1).to be > base
        expect(bcr2).to be > base
      end

      it "correctly sorts mixed versions" do
        versions = [
          described_class.new("1.6.50.bcr.2"),
          described_class.new("1.6.50"),
          described_class.new("1.6.50.bcr.1"),
          described_class.new("1.6.51"),
          described_class.new("1.6.49")
        ]

        sorted = versions.sort
        expect(sorted.map(&:to_s)).to eq(
          [
            "1.6.49",
            "1.6.50",
            "1.6.50.bcr.1",
            "1.6.50.bcr.2",
            "1.6.51"
          ]
        )
      end

      it "handles .bcr.X with higher base versions" do
        v1 = described_class.new("1.6.50.bcr.1")
        v2 = described_class.new("1.6.51")

        expect(v2).to be > v1
      end

      it "handles .bcr.X with lower base versions" do
        v1 = described_class.new("1.6.49.bcr.1")
        v2 = described_class.new("1.6.50")

        expect(v2).to be > v1
      end

      it "correctly compares equal base versions with different .bcr suffixes" do
        bcr1 = described_class.new("2.0.0.bcr.1")
        bcr5 = described_class.new("2.0.0.bcr.5")
        bcr10 = described_class.new("2.0.0.bcr.10")

        expect(bcr5).to be > bcr1
        expect(bcr10).to be > bcr5
        expect(bcr10).to be > bcr1
      end

      it "prevents downgrade from .bcr version to base version" do
        bcr1 = described_class.new("1.6.50.bcr.1")
        base = described_class.new("1.6.50")

        # bcr.1 should be considered newer, so this would be a downgrade
        expect(bcr1).to be > base
        expect(base).not_to be > bcr1
      end
    end

    describe "real-world BCR example scenarios" do
      it "handles libpng version progression correctly" do
        versions = [
          described_class.new("1.6.50"),
          described_class.new("1.6.50.bcr.1")
        ]

        latest = versions.max
        expect(latest.to_s).to eq("1.6.50.bcr.1")
      end

      it "handles progression from base to multiple .bcr patches" do
        v1 = described_class.new("1.6.50")
        v2 = described_class.new("1.6.50.bcr.1")
        v3 = described_class.new("1.6.50.bcr.2")

        expect([v1, v2, v3].max).to eq(v3)
        expect([v3, v1, v2].sort).to eq([v1, v2, v3])
      end
    end
  end
end
