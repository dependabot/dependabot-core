# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/version"

RSpec.describe Dependabot::Python::Version do
  subject(:version) { described_class.new(version_string) }
  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(true) }

      context "that includes a non-zero epoch" do
        let(:version_string) { "1!1.0.0" }
        it { is_expected.to eq(true) }
      end

      context "that includes a local version" do
        let(:version_string) { "1.0.0+abc.1" }
        it { is_expected.to eq(true) }
      end

      context "that includes a prerelease part in the initial number" do
        let(:version_string) { "2013b0" }
        it { is_expected.to eq(true) }
      end

      context "with a v-prefix" do
        let(:version_string) { "v2013" }
        it { is_expected.to eq(true) }
      end
    end

    context "with nil" do
      let(:version_string) { nil }
      it { is_expected.to eq(false) }
    end

    context "with an invalid version" do
      let(:version_string) { "bad" }
      it { is_expected.to eq(false) }

      context "that includes an invalid local version" do
        let(:version_string) { "1.0.0+abc 123" }
        it { is_expected.to eq(false) }
      end
    end
  end

  describe ".new" do
    subject { described_class.new(version_string) }

    context "with a blank string" do
      let(:version_string) { "" }
      it { is_expected.to eq(Gem::Version.new("0")) }
    end
  end

  describe "#to_s" do
    subject { version.to_s }

    context "with a normal version" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq "1.0.0" }
    end

    context "with a local version" do
      let(:version_string) { "1.0.0+gc.1" }
      it { is_expected.to eq "1.0.0+gc.1" }
    end
  end

  describe "#<=>" do
    sorted_versions = [
      "",
      "0.9",
      "1.0.0-alpha",
      "1.0.0-a.1",
      "1.0.0-beta",
      "1.0.0-b.2",
      "1.0.0-beta.11",
      "1.0.0-rc.1",
      "1",
      # "1.0.0.post", TODO fails comparing to 1
      "1.0.0+gc1",
      "1.post2",
      "1.post2+gc1",
      "1.0.0.post11",
      "1.0.1",
      "1.0.11",
      "2016.1",
      "1!0.1.0",
      "2!0.1.0",
      "10!0.1.0"
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
    end
    it "should handle missing version segments" do
      expect(described_class.new("1")).to eq "v1.0"
      expect(described_class.new("1")).to eq "v1.0.0"
    end
  end

  describe "#prerelease?" do
    subject { version.prerelease? }

    context "with a prerelease" do
      let(:version_string) { "1.0.0alpha" }
      it { is_expected.to eq(true) }
    end

    context "with a normal release" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(false) }
    end

    context "with a post release" do
      let(:version_string) { "1.0.0-post1" }
      it { is_expected.to eq(false) }

      context "that is implicit" do
        let(:version_string) { "1.0.0-1" }
        it { is_expected.to eq(false) }
      end

      context "that uses a dot" do
        let(:version_string) { "1.0.0.post1" }
        it { is_expected.to eq(false) }
      end
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

    context "with a valid local version" do
      let(:version_string) { "1.1.0+gc.1" }
      it { is_expected.to eq(true) }
    end
  end
end
