# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/apm/version"

RSpec.describe Dependabot::Apm::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.2.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a plain semver string" do
      let(:version_string) { "1.2.0" }

      it { is_expected.to be(true) }
    end

    context "with a leading v" do
      let(:version_string) { "v1.2.0" }

      it { is_expected.to be(true) }
    end

    context "with a branch name" do
      let(:version_string) { "main" }

      it { is_expected.to be(false) }
    end

    context "with a partial major-only version" do
      let(:version_string) { "1" }

      it { is_expected.to be(false) }
    end

    context "with a partial major.minor version" do
      let(:version_string) { "1.2" }

      it { is_expected.to be(false) }
    end

    context "with build metadata" do
      let(:version_string) { "1.2.0+build.5" }

      it { is_expected.to be(true) }
    end

    context "with a prerelease and build metadata" do
      let(:version_string) { "1.2.0-alpha.1+build.5" }

      it { is_expected.to be(true) }
    end

    context "with a commit SHA" do
      let(:version_string) { "0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e" }

      it { is_expected.to be(false) }
    end

    context "with an empty string" do
      let(:version_string) { "" }

      it { is_expected.to be(false) }
    end

    context "with nil" do
      let(:version_string) { nil }

      it { is_expected.to be(false) }
    end
  end

  describe "#initialize" do
    context "with a leading v" do
      let(:version_string) { "v1.2.0" }

      it "strips the v and compares equal to the plain version" do
        expect(version).to eq(described_class.new("1.2.0"))
        expect(version.to_s).to eq("1.2.0")
      end
    end

    context "without a leading v" do
      let(:version_string) { "1.2.0" }

      it "keeps the version as-is" do
        expect(version.to_s).to eq("1.2.0")
      end
    end
  end

  describe "comparison" do
    it "orders versions numerically regardless of a leading v" do
      expect(described_class.new("v1.10.0")).to be > described_class.new("1.9.0")
      expect(described_class.new("1.0.0")).to be < described_class.new("v2.0.0")
    end
  end

  describe "#bump" do
    # `~>` requirement matching calls this; the inherited Gem::Version#bump would
    # build the partial `1.3`, which strict SemVer rejects.
    it "returns the next-minor SemVer triple without raising" do
      bumped = described_class.new("1.2.3").bump
      expect(bumped).to be_a(described_class)
      expect(bumped.to_s).to eq("1.3.0")
    end
  end

  describe "SemVer precedence" do
    it "treats build metadata as equal precedence" do
      expect(described_class.new("1.2.0+build.1")).to eq(described_class.new("1.2.0+build.2"))
      expect(described_class.new("1.2.0+build.1")).to eq(described_class.new("1.2.0"))
    end

    it "ranks a prerelease below its release" do
      expect(described_class.new("1.0.0-alpha")).to be < described_class.new("1.0.0")
    end

    it "orders numeric prerelease identifiers below alphanumeric ones" do
      expect(described_class.new("1.0.0-alpha.1")).to be < described_class.new("1.0.0-alpha.beta")
    end

    it "compares numeric prerelease identifiers numerically, not lexically" do
      expect(described_class.new("1.0.0-beta.2")).to be < described_class.new("1.0.0-beta.11")
    end

    it "follows the canonical SemVer prerelease ordering" do
      ordered = %w(
        1.0.0-alpha
        1.0.0-alpha.1
        1.0.0-alpha.beta
        1.0.0-beta
        1.0.0-beta.2
        1.0.0-beta.11
        1.0.0-rc.1
        1.0.0
      ).map { |v| described_class.new(v) }

      expect(ordered.each_cons(2).all? { |a, b| a < b }).to be(true)
    end
  end
end
