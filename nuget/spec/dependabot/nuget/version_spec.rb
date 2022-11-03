# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget/version"

RSpec.describe Dependabot::Nuget::Version do
  subject(:version) { described_class.new(version_string) }
  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(true) }

      context "that includes build information" do
        let(:version_string) { "1.0.0+abc.1" }
        it { is_expected.to eq(true) }
      end

      context "that includes pre-release details" do
        let(:version_string) { "1.0.0-beta+abc.1" }
        it { is_expected.to eq(true) }
      end
    end

    context "with nil" do
      let(:version_string) { nil }
      it { is_expected.to eq(false) }
    end

    context "with a blank version" do
      let(:version_string) { "" }
      it { is_expected.to eq(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "bad" }
      it { is_expected.to eq(false) }

      context "that includes build information" do
        let(:version_string) { "1.0.0+abc 123" }
        it { is_expected.to eq(false) }
      end
    end
  end

  describe "#to_s" do
    subject { version.to_s }

    context "with a normal version" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq "1.0.0" }
    end

    context "with build information" do
      let(:version_string) { "1.0.0+gc.1" }
      it { is_expected.to eq "1.0.0" }
    end

    context "with a blank version" do
      let(:version_string) { "" }
      it { is_expected.to eq "" }
    end

    context "with pre-release details" do
      let(:version_string) { "1.0.0-beta+abc.1" }
      it { is_expected.to eq("1.0.0-beta") }
    end
  end

  describe "#<=>" do
    sorted_versions = [
      "",
      "0.9.0",
      "1.0.0-alpha",
      "1.0.0-alpha.1",
      "1.0.0-alpha.beta",
      "1.0.0-beta",
      "1.0.0-beta.2",
      "1.0.0-beta.11",
      "1.0.0-beta.11.1",
      "1.0.0-beta-extra-hyphens",
      "1.0.0-rc.1",
      "1.0.0",
      "1.0.0.1-pre",
      "1.0.0.1-pre.2",
      "1.0.0.1",
      "1.0.0.2",
      "1.1.0"
    ]
    sorted_versions.combination(2).each do |lhs, rhs|
      it "'#{lhs}' < '#{rhs}'" do
        expect(described_class.new(lhs)).to be < rhs
        expect(described_class.new(rhs)).to be > lhs
      end
    end

    sorted_versions.each do |v|
      it "should equal itself #{v}" do
        expect(described_class.new(v)).to eq v
      end
      it "should ignore the build identifier #{v}+build" do
        expect(described_class.new(v)).to eq described_class.new("#{v}+build")
      end
    end

    it "ignores case for pre-release" do
      expect(described_class.new("1.0.0-alpha")).to eq("1.0.0-ALPHA")
    end
  end

  describe "compatibility with Gem::Requirement" do
    subject { requirement.satisfied_by?(version) }
    let(:requirement) { Gem::Requirement.new(">= 1.0.0") }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "0.9.0" }
      it { is_expected.to eq(false) }
    end

    context "with a valid build information" do
      let(:version_string) { "1.1.0+gc.1" }
      it { is_expected.to eq(true) }
    end
  end
end
