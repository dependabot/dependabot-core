# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/vcpkg/version"

RSpec.describe Dependabot::Vcpkg::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a relaxed version" do
      let(:version_string) { "7.48.0" }

      it { is_expected.to be(true) }
    end

    context "with a version carrying a port version" do
      let(:version_string) { "1.2.11#9" }

      it { is_expected.to be(true) }
    end

    context "with a date version" do
      let(:version_string) { "2021-11-01" }

      it { is_expected.to be(true) }
    end

    context "with a version-string scheme value" do
      let(:version_string) { "cares-1_15_0" }

      it { is_expected.to be(true) }
    end

    context "with an OpenSSL style letter suffix" do
      let(:version_string) { "1.1.1n" }

      it { is_expected.to be(true) }
    end

    context "with a bare commit SHA" do
      let(:version_string) { "fe1cde61e971d53c9687cf9a46308f8f55da19fa" }

      it "is rejected so registry baselines stay recognizable as git SHAs" do
        expect(described_class.correct?(version_string)).to be(false)
      end
    end

    context "with a digits-only value that could be a SHA prefix" do
      let(:version_string) { "1234567" }

      it { is_expected.to be(true) }
    end

    context "with a port version marker that has no number" do
      let(:version_string) { "1.2.3#" }

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

  describe "#comparison_class" do
    subject { described_class.new(version_string).comparison_class }

    context "with dot-separated numerics" do
      let(:version_string) { "1.2.3" }

      it { is_expected.to eq(:dot) }
    end

    context "with a semver pre-release" do
      let(:version_string) { "1.0.0-alpha.1" }

      it { is_expected.to eq(:dot) }
    end

    context "with a date" do
      let(:version_string) { "2021-11-01" }

      it "prefers the date scheme over the dot scheme" do
        expect(described_class.new(version_string).comparison_class).to eq(:date)
      end
    end

    context "with a date carrying a disambiguator" do
      let(:version_string) { "2021-11-01.1" }

      it { is_expected.to eq(:date) }
    end

    context "with an arbitrary string" do
      let(:version_string) { "1.0.2h-1" }

      it { is_expected.to eq(:string) }
    end
  end

  describe "#port_version" do
    context "with an explicit port version" do
      let(:version_string) { "1.2.11#9" }

      its(:port_version) { is_expected.to eq(9) }
    end

    context "without a port version" do
      let(:version_string) { "1.2.11" }

      its(:port_version) { is_expected.to eq(0) }
    end
  end

  describe "#to_s" do
    context "with a port version" do
      let(:version_string) { "1.2.11#9" }

      its(:to_s) { is_expected.to eq("1.2.11#9") }
    end

    context "with a pre-release" do
      let(:version_string) { "1.0.0-alpha.1" }

      it "does not mangle the pre-release separator" do
        expect(version.to_s).to eq("1.0.0-alpha.1")
      end
    end

    context "with a version-string scheme value" do
      let(:version_string) { "cares-1_15_0" }

      its(:to_s) { is_expected.to eq("cares-1_15_0") }
    end
  end

  describe "#prerelease?" do
    context "with a semver pre-release" do
      let(:version_string) { "1.0.0-alpha" }

      its(:prerelease?) { is_expected.to be(true) }
    end

    context "with a release version" do
      let(:version_string) { "1.0.0" }

      its(:prerelease?) { is_expected.to be(false) }
    end

    context "with a string scheme value that looks like a pre-release" do
      let(:version_string) { "3.0.5rc2" }

      its(:prerelease?) { is_expected.to be(false) }
    end
  end

  describe "#<=>" do
    # Orderings taken from https://learn.microsoft.com/vcpkg/users/versioning#version-schemes
    {
      %w(0 0.1) => -1,
      %w(0.1 0.1.0) => -1,
      %w(0.1.0 1) => -1,
      %w(1 1.0.0) => -1,
      %w(1.0.0 1.0.1) => -1,
      %w(1.0.1 1.1) => -1,
      %w(1.1 2.0.0) => -1,
      %w(1.0.0-1 1.0.0-alpha) => -1,
      %w(1.0.0-alpha 1.0.0-beta) => -1,
      %w(1.0.0-beta 1.0.0) => -1,
      %w(2021-01-01 2021-01-01.1) => -1,
      %w(2021-01-01.1 2021-02-01.1.2) => -1,
      %w(2021-02-01.1.2 2021-02-01.1.3) => -1,
      %w(1.2.0 1.2.0#1) => -1,
      %w(1.2.0#1 1.2.0#2) => -1,
      %w(1.2.0#2 1.2.0#10) => -1,
      %w(watermelon#0 watermelon#1) => -1,
      %w(1.2.3 1.2.3) => 0
    }.each do |(left, right), expected|
      it "orders #{left} against #{right}" do
        expect(described_class.new(left) <=> described_class.new(right)).to eq(expected)
      end
    end

    it "ignores build metadata when comparing the numeric core" do
      expect(described_class.new("1.2.3+build") <=> described_class.new("1.2.3")).to eq(0)
    end

    it "returns a total order for incomparable schemes so release lists can be sorted" do
      expect(described_class.new("1.2.3") <=> described_class.new("2021-01-01")).not_to be_nil
    end

    it "returns nil when the other value is not a version" do
      expect(version <=> Object.new).to be_nil
    end

    it "compares against a plain string" do
      expect(described_class.new("1.2.3") <=> "1.2.4").to eq(-1)
    end
  end

  describe "#comparable_with?" do
    {
      %w(1.2.3 1.3.0) => true,
      %w(1.0.0-alpha 2.0.0) => true,
      %w(2021-01-01 2021-02-01) => true,
      %w(apple apple) => true,
      %w(apple orange) => false,
      %w(1.2.3 2021-01-01) => false,
      %w(1.1.1n 1.1.1w) => false,
      %w(1.2.3 1.0.2h) => false
    }.each do |(left, right), expected|
      it "reports #{left} and #{right} as #{expected ? 'comparable' : 'incomparable'}" do
        expect(described_class.new(left).comparable_with?(described_class.new(right))).to be(expected)
      end
    end
  end

  describe "#eql? and #hash" do
    it "treats identical versions as equal" do
      other = described_class.new("1.2.11#9")

      expect(described_class.new("1.2.11#9")).to eql(other)
    end

    it "distinguishes versions that differ only by port version" do
      expect(described_class.new("1.2.11#9")).not_to eql(described_class.new("1.2.11"))
    end

    it "keeps distinct string scheme versions distinct when deduplicating" do
      versions = %w(apple orange banana apple).map { |string| described_class.new(string) }

      expect(versions.uniq.map(&:to_s)).to contain_exactly("apple", "orange", "banana")
    end
  end

  describe "sorting a mixed release list" do
    it "does not raise" do
      versions = %w(1.2.3 2021-01-01 cares-1_15_0 1.0.2h 1.2.3#4).map { |string| described_class.new(string) }

      expect { versions.sort }.not_to raise_error
    end
  end
end
