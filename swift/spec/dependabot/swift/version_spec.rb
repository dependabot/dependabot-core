# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/version"

RSpec.describe Dependabot::Swift::Version do
  describe ".correct?" do
    it "returns true for standard versions" do
      expect(described_class.correct?("1.0.0")).to be true
      expect(described_class.correct?("0.1.0")).to be true
      expect(described_class.correct?("10.20.30")).to be true
    end

    it "returns true for prerelease versions" do
      expect(described_class.correct?("1.0.0-alpha.1")).to be true
      expect(described_class.correct?("1.0.0-beta.2")).to be true
      expect(described_class.correct?("1.0.0-rc.1")).to be true
      expect(described_class.correct?("2.0.0-0.3.7")).to be true
    end

    it "returns true for versions with build metadata" do
      expect(described_class.correct?("1.0.0+build")).to be true
      expect(described_class.correct?("1.0.0+build.123")).to be true
      expect(described_class.correct?("1.0.0-beta.1+build.456")).to be true
    end

    it "returns false for non-version strings" do
      expect(described_class.correct?("potato")).to be false
      expect(described_class.correct?("")).to be false
      expect(described_class.correct?(nil)).to be false
    end

    it "returns false for non-SemVer (Gem-style) versions" do
      expect(described_class.correct?("1.0.0.alpha")).to be false
      expect(described_class.correct?("0.0.0.0")).to be false
      expect(described_class.correct?("01.2.3")).to be false
    end

    it "rejects prerelease identifiers with leading zeros" do
      expect(described_class.correct?("1.0.0-01")).to be false
      expect(described_class.correct?("1.0.0-0.1")).to be true
    end

    it "rejects multiline strings (anchors to the whole string)" do
      expect(described_class.correct?("1.0.0\ninvalid")).to be false
    end

    it "returns false for invalid build metadata" do
      expect(described_class.correct?("1.0.0+")).to be false
      expect(described_class.correct?("1.0.0+bad@")).to be false
    end

    it "returns true for v-prefixed versions" do
      expect(described_class.correct?("v1.0.0")).to be true
      expect(described_class.correct?("v1.0.0-alpha.1")).to be true
      expect(described_class.correct?("v2.3.4+build")).to be true
    end
  end

  describe ".new" do
    it "creates a version from a standard string" do
      version = described_class.new("1.0.0")
      expect(version.to_s).to eq("1.0.0")
    end

    it "handles v-prefixed versions" do
      version = described_class.new("v1.2.3")
      expect(version.to_s).to eq("v1.2.3")
      expect(version).to eq(described_class.new("1.2.3"))
    end

    it "preserves build metadata in to_s" do
      version = described_class.new("1.0.0+build123")
      expect(version.to_s).to eq("1.0.0+build123")
    end

    it "strips build metadata for comparison" do
      v1 = described_class.new("1.0.0+build1")
      v2 = described_class.new("1.0.0+build2")
      v3 = described_class.new("1.0.0")
      expect(v1).to eq(v2)
      expect(v1).to eq(v3)
    end

    it "rejects malformed build/prerelease forms via .correct?" do
      expect(described_class.correct?("1.0.0+")).to be false
      expect(described_class.correct?("1.0.0-")).to be false
    end

    it "preserves a hyphenated pre-release identifier as a single SemVer token" do
      # "alpha-1" is one SemVer identifier and must not be split on the hyphen.
      version = described_class.new("1.0.0-alpha-1")
      expect(version.to_semver).to eq("1.0.0-alpha-1")
      expect(version).to be > described_class.new("1.0.0-alpha.1")
    end

    it "tolerantly constructs non-SemVer tags (sorting by their numeric core) without raising" do
      # The shared GitCommitChecker builds versions for any VERSION_REGEX-matching tag, so
      # construction must not raise even though .correct? rejects these as non-SemVer.
      expect(described_class.correct?("0.0.0.0")).to be false
      version = described_class.new("0.0.0.0")
      expect(version.to_s).to eq("0.0.0.0")
      expect(version).to be < described_class.new("0.0.1")
    end

    it "keeps a Gem-style non-SemVer tag sorting below its release (not masquerading as stable)" do
      # "1.0.0.alpha" is rejected by .correct?, but the tolerant path must not coerce it
      # into a stable 1.0.0: its non-numeric tail is surfaced as an inferred pre-release.
      expect(described_class.correct?("1.0.0.alpha")).to be false
      version = described_class.new("1.0.0.alpha")
      expect(version.to_s).to eq("1.0.0.alpha")
      expect(version.prerelease?).to be true
      expect(version).to be < described_class.new("1.0.0")
    end

    it "tolerantly constructs tags with a SemVer-invalid explicit suffix without raising" do
      # GitCommitChecker builds versions for any VERSION_REGEX tag, including "1.0.0-01"/"1.0.0-",
      # whose suffix is not valid SemVer; construction must not raise.
      expect { described_class.new("1.0.0-01") }.not_to raise_error
      expect { described_class.new("1.0.0-") }.not_to raise_error
    end

    it "treats an empty explicit suffix as a pre-release that sorts below the release" do
      # "1.0.0-" must not masquerade as the stable "1.0.0" (which would let it survive prerelease
      # filtering as a stable maximum).
      version = described_class.new("1.0.0-")
      expect(version.prerelease?).to be true
      expect(version).to be < described_class.new("1.0.0")
    end

    it "treats a RubyGems-normalized prerelease tag as a pre-release" do
      version = described_class.new("2.54.0.pre.beta.1")
      expect(version.prerelease?).to be true
      expect(version).to be < described_class.new("2.54.0")
    end
  end

  describe "#to_semver" do
    it "returns version without build metadata" do
      expect(described_class.new("1.0.0-rc.1+build").to_semver).to eq("1.0.0-rc.1")
    end

    it "returns full version when no build metadata" do
      expect(described_class.new("1.0.0-alpha.1").to_semver).to eq("1.0.0-alpha.1")
    end

    it "returns numeric version for stable releases" do
      expect(described_class.new("2.3.4").to_semver).to eq("2.3.4")
    end
  end

  describe "#prerelease?" do
    it "returns false for stable versions" do
      expect(described_class.new("1.0.0").prerelease?).to be false
    end

    it "returns false for versions with only build metadata" do
      expect(described_class.new("1.0.0+build").prerelease?).to be false
    end

    it "returns true for prerelease versions" do
      expect(described_class.new("1.0.0-alpha.1").prerelease?).to be true
      expect(described_class.new("1.0.0-beta.2").prerelease?).to be true
      expect(described_class.new("1.0.0-rc.1").prerelease?).to be true
    end

    it "returns true for prerelease with build metadata" do
      expect(described_class.new("1.0.0-rc.1+build").prerelease?).to be true
    end
  end

  describe "comparison" do
    it "orders prereleases before stable" do
      expect(described_class.new("1.0.0-beta.1")).to be < described_class.new("1.0.0")
    end

    it "orders versions numerically" do
      expect(described_class.new("1.9.0")).to be < described_class.new("1.10.0")
    end

    it "ignores build metadata in ordering" do
      v1 = described_class.new("1.0.0+build1")
      v2 = described_class.new("1.0.0+build2")
      expect(v1).to eq(v2)
      expect(v1).not_to be > v2
    end

    it "returns nil for non-version strings" do
      v = described_class.new("1.0.0")
      expect(v <=> "potato").to be_nil
    end

    it "returns nil (never raises) for a hostile operand whose #to_s raises" do
      hostile = Object.new
      def hostile.to_s = raise("boom")

      expect(described_class.new("1.0.0") <=> hostile).to be_nil
    end

    it "compares Gem-style pre-release formats via Gem::Version fallback" do
      v = described_class.new("1.0.0")
      expect(v <=> "1.0.0.alpha").to eq(1)
    end

    it "ignores build metadata on a non-Version operand (does not return nil)" do
      # Build metadata is ignored for comparison even when the operand is a bare string
      # whose "+build" RubyGems cannot parse.
      expect(described_class.new("1.0.0") <=> "1.0.0+build").to eq(0)
    end

    it "returns nil for a malformed '+' operand" do
      # Only genuinely valid SemVer build metadata is stripped; junk stays invalid.
      expect(described_class.new("1.0.0") <=> "1.0.0++").to be_nil
    end

    it "compares symmetrically against a plain Gem::Version pre-release/release boundary" do
      # The Gem superclass is seeded with the full pre-release-aware version, so the reverse
      # `Gem::Version <=> Swift::Version` direction is not seen as a bare (stable) release.
      swift_prerelease = described_class.new("1.0.0-alpha")
      gem_release = Gem::Version.new("1.0.0")

      expect(swift_prerelease <=> gem_release).to eq(-1)
      expect(gem_release <=> swift_prerelease).to eq(1)
    end

    it "orders a SemVer string operand by section 11, consistent with Swift-vs-Swift" do
      expect(described_class.new("1.0.0-1") <=> "1.0.0-alpha").to eq(-1)
      expect(described_class.new("1.0.0-alpha") <=> "1.0.0-1").to eq(1)
    end

    it "declines to order an ambiguous raw Gem::Version pre-release (returns nil)" do
      # A Gem::Version pre-release has a lossy #to_s and RubyGems orders identifiers differently,
      # so ordering it against section 11 would be inconsistent; refuse rather than guess.
      expect(described_class.new("1.0.0-1") <=> Gem::Version.new("1.0.0-1")).to be_nil
    end

    it "returns nil for nil" do
      v = described_class.new("1.0.0")
      expect(v <=> nil).to be_nil
    end

    it "distinguishes prereleases in hash/eql?" do
      v1 = described_class.new("1.0.0-alpha")
      v2 = described_class.new("1.0.0-beta")
      expect(v1.eql?(v2)).to be false
      expect(v1.hash).not_to eq(v2.hash)
    end

    it "treats build metadata variants as eql? in hash" do
      v1 = described_class.new("1.0.0+build1")
      v2 = described_class.new("1.0.0+build2")
      expect(v1.eql?(v2)).to be true
      expect(v1.hash).to eq(v2.hash)
    end

    it "handles hyphenated prerelease identifiers" do
      v1 = described_class.new("1.0.0-alpha-1")
      v2 = described_class.new("1.0.0-alpha.1")
      expect(v1).to be > v2
    end

    it "compares across different major versions with prereleases" do
      expect(described_class.new("1.0.0-alpha")).to be < described_class.new("2.0.0-alpha")
      expect(described_class.new("2.0.0-alpha")).to be > described_class.new("1.0.0")
    end

    describe "#==" do
      it "does not treat a prerelease as equal to its release" do
        expect(described_class.new("1.0.0-alpha") == described_class.new("1.0.0")).to be false
      end

      it "does not treat distinct prereleases as equal" do
        expect(described_class.new("1.0.0-alpha") == described_class.new("1.0.0-beta")).to be false
      end

      it "treats versions differing only in build metadata as equal" do
        expect(described_class.new("1.0.0+build1") == described_class.new("1.0.0+build2")).to be true
      end

      it "returns false for non-version values" do
        expect(described_class.new("1.0.0") == "potato").to be false
      end
    end

    context "with SemVer section 11 pre-release precedence" do
      it "orders numeric identifiers before alphanumeric" do
        expect(described_class.new("1.0.0-1")).to be < described_class.new("1.0.0-alpha")
      end

      it "orders fewer fields before more fields" do
        expect(described_class.new("1.0.0-alpha")).to be < described_class.new("1.0.0-alpha.1")
      end

      it "orders alphanumeric after numeric in mixed comparisons" do
        expect(described_class.new("1.0.0-alpha.1")).to be < described_class.new("1.0.0-alpha.beta")
      end

      it "follows full SemVer section 11 example ordering" do
        versions = %w(
          1.0.0-alpha
          1.0.0-alpha.1
          1.0.0-alpha.beta
          1.0.0-beta
          1.0.0-beta.2
          1.0.0-beta.11
          1.0.0-rc.1
          1.0.0
        )

        parsed = versions.map { |v| described_class.new(v) }
        expect(parsed.shuffle.sort).to eq(parsed)
      end

      it "compares numeric identifiers as integers, not strings" do
        expect(described_class.new("1.0.0-beta.2")).to be < described_class.new("1.0.0-beta.11")
      end
    end
  end
end
