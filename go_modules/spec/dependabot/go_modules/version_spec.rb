# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/version"

RSpec.describe Dependabot::GoModules::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.0.0" }

  describe ".pseudo_version?" do
    subject { described_class.pseudo_version?(version_string) }

    context "with a standard pseudo-version (no prior tag)" do
      let(:version_string) { "v0.0.0-20180826012351-8a410e7b638d" }

      it { is_expected.to be(true) }
    end

    context "with a pseudo-version after a pre-release tag" do
      let(:version_string) { "v1.4.0-rc1.0.20250929141436-dad09ab05b71" }

      it { is_expected.to be(true) }
    end

    context "with a pseudo-version after a release tag" do
      let(:version_string) { "v1.0.1-0.20231231120000-abcdefabcdef" }

      it { is_expected.to be(true) }
    end

    context "with a normal version" do
      let(:version_string) { "v1.0.0" }

      it { is_expected.to be(false) }
    end

    context "with a pre-release version" do
      let(:version_string) { "v1.0.0-rc1" }

      it { is_expected.to be(false) }
    end

    context "with nil" do
      let(:version_string) { nil }

      it { is_expected.to be(false) }
    end

    context "with an incompatible version" do
      let(:version_string) { "v3.0.0+incompatible" }

      it { is_expected.to be(false) }
    end
  end

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a string prefixed with a 'v'" do
      let(:version_string) { "v1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with a string not prefixed with a 'v'" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with an 'incompatible' suffix" do
      let(:version_string) { "v1.0.0+incompatible" }

      it { is_expected.to be(true) }
    end

    context "with an invalid string" do
      let(:version_string) { "va1.0.0" }

      it { is_expected.to be(false) }
    end

    context "with an empty string" do
      let(:version_string) { "" }

      it { is_expected.to be(true) }
    end
  end

  describe "#to_s" do
    subject { version.to_s }

    context "with a non-prerelease" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to eq "1.0.0" }
    end

    context "with a normal prerelease" do
      let(:version_string) { "1.0.0.pre1" }

      it { is_expected.to eq "1.0.0.pre1" }
    end

    context "with a PHP-style prerelease" do
      let(:version_string) { "1.0.0-pre1" }

      it { is_expected.to eq "1.0.0-pre1" }
    end

    context "with a leading v" do
      let(:version_string) { "v1.0.0" }

      it { is_expected.to eq "1.0.0" }
    end

    context "with an empty string" do
      let(:version_string) { "" }

      it { is_expected.to eq "" }
    end
  end

  describe "#inspect" do
    subject(:version_inspect) { version.inspect }

    context "with a version that Gem::Version would mangle" do
      let(:version_string) { "1.0.0-pre1" }

      it "doesn't mangle it" do
        expect(version_inspect).to eq "#<Dependabot::GoModules::Version \"1.0.0-pre1\">"
      end
    end
  end

  describe "compatibility with Gem::Requirement" do
    subject { requirement.satisfied_by?(version) }

    let(:requirement) { Gem::Requirement.new(">= 1.0.0") }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with an 'incompatible' suffix" do
      let(:version_string) { "1.0.0+incompatible" }

      it { is_expected.to be(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "0.9.0" }

      it { is_expected.to be(false) }
    end

    context "with a valid prerelease version" do
      let(:version_string) { "1.1.0-pre" }

      it { is_expected.to be(true) }
    end

    context "when prefixed with a 'v'" do
      context "with a greater version" do
        let(:version_string) { "v1.1.0" }

        it { is_expected.to be(true) }
      end

      context "with an lesser version" do
        let(:version_string) { "v0.9.0" }

        it { is_expected.to be(false) }
      end
    end
  end

  describe "<=>" do
    # These identifiers come from the Go docs: https://go.dev/ref/mod#pseudo-versions
    it "sorts major versions correctly" do
      expect(described_class.new("v1.0.0-0.20231231120000-abcdefabcdef")).to be < described_class.new("v1.0.0")
    end

    it "sorts pre-release versions correctly" do
      expect(described_class.new("v1.0.0-pre2.0.20231231120000-abcdefabcdef")).to be >
                                                                                  described_class.new("v1.0.0-pre2")
    end

    it "sorts minor versions correctly" do
      expect(described_class.new("v1.0.1-0.20231231120000-abcdefabcdef")).to be < described_class.new("v1.0.1")
    end

    # See also the companion Go program that verifies the version order matches.
    sorted_versions = JSON.parse(fixture("ordered_versions.json"))
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
  end
end
