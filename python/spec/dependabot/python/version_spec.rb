# typed: false
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

      it { is_expected.to be(true) }

      context "when version includes a non-zero epoch" do
        let(:version_string) { "1!1.0.0" }

        it { is_expected.to be(true) }
      end

      context "when version includes a local version" do
        let(:version_string) { "1.0.0+abc.1" }

        it { is_expected.to be(true) }
      end

      context "when version includes a prerelease part in the initial number" do
        let(:version_string) { "2013b0" }

        it { is_expected.to be(true) }
      end

      context "with a v-prefix" do
        let(:version_string) { "v2013" }

        it { is_expected.to be(true) }
      end
    end

    context "with nil" do
      let(:version_string) { nil }

      it { is_expected.to be(false) }
    end

    context "with invalid versions" do
      versions = [
        "bad",
        "1.0+a+",
        "1.0++",
        "1.0+_foobar",
        "1.0+foo&asd",
        "1.0+1+1",
        "1.0.0+abc 123",
        "v1.8.0--failed-release-attempt"
      ]

      versions.each do |version|
        it "returns false for #{version}" do
          expect(described_class.correct?(version)).to be false
        end
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
      "1.post2+gc1.2",
      "1.post2+gc1.11",
      "1.0.0.post11",
      "1.0.2",
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
      it "equals itself #{v}" do
        expect(described_class.new(v)).to eq v
      end
    end

    it "handles missing version segments" do
      expect(described_class.new("1")).to eq "v1.0"
      expect(described_class.new("1")).to eq "v1.0.0"
    end
  end

  describe "#prerelease?" do
    subject { version.prerelease? }

    context "with a prerelease" do
      versions =
        [
          "1.0.dev0",
          "1.0.dev1",
          "1.0a1.dev1",
          "1.0b1.dev1",
          "1.0c1.dev1",
          "1.0rc1.dev1",
          "1.0a1",
          "1.0b1",
          "1.0c1",
          "1.0rc1",
          "1.0a1.post1.dev1",
          "1.0b1.post1.dev1",
          "1.0c1.post1.dev1",
          "1.0rc1.post1.dev1",
          "1.0a1.post1",
          "1.0b1.post1",
          "1.0c1.post1",
          "1.0rc1.post1"
        ]

      versions.each do |version|
        it "returns true for #{version}" do
          expect(described_class.new(version).prerelease?).to be true
        end
      end
    end

    context "with a normal release" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(false) }
    end

    context "with a post release" do
      let(:version_string) { "1.0.0-post1" }

      it { is_expected.to be(false) }

      context "when version is implicit" do
        let(:version_string) { "1.0.0-1" }

        it { is_expected.to be(false) }
      end

      context "when using a dot" do
        let(:version_string) { "1.0.0.post1" }

        it { is_expected.to be(false) }
      end
    end

    context "with a dev release" do
      let(:version_string) { "1.0+dev" }

      it { is_expected.to be(false) }
    end

    context "with a dev release" do
      let(:version_string) { "1.0.post1+dev" }

      it { is_expected.to be(false) }
    end
  end

  describe "compatibility with Gem::Requirement" do
    subject { requirement.satisfied_by?(version) }

    let(:requirement) { Gem::Requirement.new(">= 1.0.0") }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "0.9.0" }

      it { is_expected.to be(false) }
    end

    context "with a valid local version" do
      let(:version_string) { "1.1.0+gc.1" }

      it { is_expected.to be(true) }
    end
  end
end
