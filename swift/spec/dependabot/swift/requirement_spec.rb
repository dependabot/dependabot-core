# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/requirement"
require "dependabot/swift/version"

RSpec.describe Dependabot::Swift::Requirement do
  describe "#satisfied_by?" do
    subject(:satisfied_by?) { requirement.satisfied_by?(Dependabot::Swift::Version.new(version)) }

    let(:requirement) { described_class.new(">= 2.54.0, < 3.0.0") }

    context "with a version inside the range" do
      let(:version) { "2.55.0" }

      it { is_expected.to be true }
    end

    context "with the lower boundary" do
      let(:version) { "2.54.0" }

      it { is_expected.to be true }
    end

    context "with a version below the lower boundary" do
      let(:version) { "2.53.0" }

      it { is_expected.to be false }
    end

    context "with a version at the upper boundary" do
      let(:version) { "3.0.0" }

      it { is_expected.to be false }
    end
  end

  describe "#satisfied_by? with the default '>= 0' requirement" do
    subject(:satisfied_by?) { requirement.satisfied_by?(Dependabot::Swift::Version.new(version)) }

    let(:requirement) { described_class.new(">= 0") }
    let(:version) { "1.0.0" }

    # '>= 0' resolves to Gem's DefaultRequirement whose boundary is a plain Gem::Version(0);
    # comparison must not raise.
    it { is_expected.to be true }
  end

  describe "#satisfied_by? with pre-release boundaries (SemVer section 11)" do
    subject(:satisfied_by?) { requirement.satisfied_by?(Dependabot::Swift::Version.new(version)) }

    context "when numeric identifiers rank below alphanumeric" do
      let(:requirement) { described_class.new(">= 1.0.0-1") }

      context "with an alphanumeric prerelease above the numeric boundary" do
        let(:version) { "1.0.0-alpha" }

        it { is_expected.to be true }
      end
    end

    context "when the boundary is alphanumeric" do
      let(:requirement) { described_class.new(">= 1.0.0-alpha") }

      context "with a numeric prerelease below it" do
        let(:version) { "1.0.0-1" }

        it { is_expected.to be false }
      end

      context "with more pre-release fields sharing the prefix" do
        let(:version) { "1.0.0-alpha.1" }

        it { is_expected.to be true }
      end
    end

    context "with a numeric pre-release range" do
      let(:requirement) { described_class.new("< 1.0.0-beta.11") }

      context "with a lower numeric identifier (not lexical)" do
        let(:version) { "1.0.0-beta.2" }

        it { is_expected.to be true }
      end
    end

    context "when a pre-release is below its final release" do
      let(:requirement) { described_class.new(">= 1.0.0") }

      let(:version) { "1.0.0-rc.1" }

      it { is_expected.to be false }
    end

    context "with a multi-segment numeric boundary" do
      # Multi-segment bounds (e.g. ">= 4.2.5.1") must keep full precision, not truncate to 4.2.5.
      let(:requirement) { described_class.new(">= 4.2.5.1") }

      context "with the lower three-segment version" do
        let(:version) { "4.2.5" }

        it { is_expected.to be false }
      end

      context "with the exact four-segment version" do
        let(:version) { "4.2.5.1" }

        it { is_expected.to be true }
      end
    end
  end

  describe "#satisfied_by? with a pessimistic '~>' constraint" do
    subject(:satisfied_by?) { requirement.satisfied_by?(Dependabot::Swift::Version.new(version)) }

    # '~>' is reachable via config ignored_versions (UpdateCheckers::Base#ignore_requirements),
    # so the bump upper bound must derive from the full-precision release core, not the seed.
    context "with a two-segment bound '~> 1.0' (upper bound 2.0)" do
      let(:requirement) { described_class.new("~> 1.0") }

      it { expect(requirement.satisfied_by?(Dependabot::Swift::Version.new("1.5.0"))).to be true }
      it { expect(requirement.satisfied_by?(Dependabot::Swift::Version.new("2.0.0"))).to be false }
    end

    context "with a multi-segment bound '~> 4.2.5.1' (upper bound 4.2.6)" do
      let(:requirement) { described_class.new("~> 4.2.5.1") }

      it { expect(requirement.satisfied_by?(Dependabot::Swift::Version.new("4.2.5.9"))).to be true }
      it { expect(requirement.satisfied_by?(Dependabot::Swift::Version.new("4.2.6.0"))).to be false }
    end
  end

  describe "#satisfied_by? with build metadata" do
    subject(:satisfied_by?) { requirement.satisfied_by?(Dependabot::Swift::Version.new(version)) }

    # SemVer build metadata is ignored for comparison and must not raise BadRequirementError.
    let(:requirement) { described_class.new("= 1.0.0+build") }

    let(:version) { "1.0.0" }

    it { is_expected.to be true }
  end

  describe "with malformed build metadata" do
    # Only well-formed build metadata is accepted by the grammar; malformed "+" forms are rejected.
    ["= 1.0.0+build.", "= 1.0.0+foo+bar", "= 1.0.0+", "= 1.0.0+."].each do |requirement|
      it "raises BadRequirementError for #{requirement.inspect}" do
        expect { described_class.new(requirement) }
          .to raise_error(Dependabot::BadRequirementError)
      end
    end
  end

  describe "with malformed prerelease identifiers" do
    # Prerelease tails must be non-empty dot-separated SemVer identifiers.
    ["= 1.0.0-", "= 1.0.0-alpha..1", "= 1.0.0-.1"].each do |requirement|
      it "raises BadRequirementError for #{requirement.inspect}" do
        expect { described_class.new(requirement) }
          .to raise_error(Dependabot::BadRequirementError)
      end
    end
  end

  describe "with SemVer-invalid leading zeros" do
    # SemVer forbids leading zeros in numeric identifiers; the grammar rejects them.
    ["= 01.2.3", "= 1.0.0-01"].each do |requirement|
      it "raises BadRequirementError for #{requirement.inspect}" do
        expect { described_class.new(requirement) }
          .to raise_error(Dependabot::BadRequirementError)
      end
    end
  end

  describe ".parse" do
    it "preserves a supplied Swift::Version (already section 11-aware)" do
      version = Dependabot::Swift::Version.new("1.0.0-alpha")
      operator, boundary = described_class.parse(version)

      expect(operator).to eq("=")
      expect(boundary).to equal(version)
    end

    it "converts a raw stable Gem::Version boundary into a matchable Swift::Version" do
      # A raw Gem::Version boundary would be declined by Version#<=>, so an exact requirement
      # could silently never match. Converting keeps the boundary orderable and usable.
      operator, boundary = described_class.parse(Gem::Version.new("1.2.3"))

      expect(operator).to eq("=")
      expect(boundary).to be_a(Dependabot::Swift::Version)
      expect(boundary).to eq(Dependabot::Swift::Version.new("1.2.3"))
    end

    it "rejects a prerelease Gem::Version whose #to_s is lossily canonicalized" do
      # Gem::Version.new("1.0.0-alpha").to_s is "1.0.0.pre.alpha", which would parse into a
      # different SemVer prerelease, so an exact requirement would never match the real version.
      expect { described_class.parse(Gem::Version.new("1.0.0-alpha")) }
        .to raise_error(Dependabot::BadRequirementError)
    end
  end
end
