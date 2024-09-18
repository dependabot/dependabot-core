# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/version"

RSpec.describe Dependabot::Maven::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a normal version" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with a normal version" do
      let(:version_string) { "Finchley" }

      it { is_expected.to be(true) }
    end

    context "with a dynamic version" do
      let(:version_string) { "1.+" }

      it { is_expected.to be(true) }
    end

    context "with a nil version" do
      let(:version_string) { nil }

      it { is_expected.to be(false) }
    end

    context "with an empty version" do
      let(:version_string) { "" }

      it { is_expected.to be(false) }
    end

    context "with a malformed version string" do
      let(:version_string) { "-" }

      it { is_expected.to be(false) }
    end
  end

  describe "#to_s" do
    subject { version.to_s }

    context "with no dashes" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to eq("1.0.0") }
    end

    context "with a + separated build number" do
      let(:version_string) { "1.0.0+100" }

      it { is_expected.to eq("1.0.0+100") }
    end

    context "with a + separated alphanumeric build identifier" do
      let(:version_string) { "1.0.0+build1" }

      it { is_expected.to eq("1.0.0+build1") }
    end

    context "with a dot-specified prerelease" do
      let(:version_string) { "1.0.0.pre1" }

      it { is_expected.to eq("1.0.0.pre1") }
    end

    context "with a dash-specified prerelease" do
      let(:version_string) { "1.0.0-pre1" }

      it { is_expected.to eq("1.0.0-pre1") }
    end

    context "with an underscore-specified prerelease" do
      let(:version_string) { "1.0.0_pre1" }

      it { is_expected.to eq("1.0.0_pre1") }
    end

    context "with a nil version" do
      let(:version_string) { nil }
      let(:err_msg) { "Malformed version string - string is nil" }

      it "raises an exception" do
        expect { version }.to raise_error(Dependabot::BadRequirementError, err_msg)
      end
    end

    context "with an empty version" do
      let(:version_string) { "" }
      let(:err_msg) { "Malformed version string - string is empty" }

      it "raises an exception" do
        expect { version }.to raise_error(Dependabot::BadRequirementError, err_msg)
      end
    end

    context "with a malformed version string" do
      let(:version_string) { "-" }
      let(:err_msg) { "Malformed version string - #{version_string}" }

      it "raises an exception" do
        expect { version }.to raise_error(Dependabot::BadRequirementError, err_msg)
      end
    end
  end

  describe "#prerelease?" do
    subject { version.prerelease? }

    context "with an alpha" do
      let(:version_string) { "1.0.0-alpha" }

      it { is_expected.to be(true) }
    end

    context "with a capitalised alpha" do
      let(:version_string) { "1.0.0-Alpha" }

      it { is_expected.to be(true) }
    end

    context "with an alpha separated with a ." do
      let(:version_string) { "1.0.0.alpha" }

      it { is_expected.to be(true) }
    end

    context "with an alpha with no separator" do
      let(:version_string) { "1.0.0alpha" }

      it { is_expected.to be(true) }
    end

    context "with an alligator" do
      let(:version_string) { "1.0.0alligator" }

      it { is_expected.to be(false) }
    end

    context "with a release" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(false) }
    end

    context "with a post-release" do
      let(:version_string) { "1.0.0.sp7" }

      it { is_expected.to be(false) }
    end
  end

  describe "#inspect" do
    subject { described_class.new(version_string).inspect }

    let(:version_string) { "1.0.0+build1" }

    it { is_expected.to eq("#<#{described_class} #{version_string}>") }
  end

  describe "#to_semver" do
    subject { described_class.new(version_string).to_semver }

    let(:version_string) { "1.0.0+build1" }

    it { is_expected.to eq version_string }
  end

  describe "#<=>" do
    subject { version.send(:<=>, other_version) }

    context "when comparing to a Gem::Version" do
      context "when lower" do
        let(:other_version) { Gem::Version.new("0.9.0") }

        it { is_expected.to eq(1) }
      end

      context "when equal" do
        let(:other_version) { Gem::Version.new("1.0.0") }

        it { is_expected.to eq(0) }
      end

      context "when greater" do
        let(:other_version) { Gem::Version.new("1.1.0") }

        it { is_expected.to eq(-1) }
      end
    end

    context "with semantic versions" do
      let(:versions) do
        [
          ["1.2.3", "1.2.2", 1],
          ["1.2.3", "1.2.3", 0],
          ["1.2.3", "v1.2.3", 0]
        ]
      end

      it "returns the correct result" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "with semantic versions that have a build number" do
      let(:versions) do
        [
          ["1.2.3", "1.2.3-1", -1],
          ["1.2.3", "1.2.3-0-1", -1],
          ["1.2.3", "1.2.3-0.1", -1],
          ["1.2.3-2", "1.2.3-1", 1],
          ["1.2.3-0.2", "1.2.3-1.1", -1]
        ]
      end

      it "returns the correct result" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "with semantic versions that have a qualifier" do
      let(:versions) do
        [
          ["1.2.3", "1.2.3-a0", 1], # alpha has lower precedence
          ["1.2.3", "1.2.3-a", -1] # 'a' without a following int is not alpha

        ]
      end

      it "returns the correct result" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "with versions that have trailing nulls" do
      let(:versions) do
        [
          ["1alpha-0", "1alpha", 0],
          ["1alpha-0", "1alpha0", 0],
          ["1alpha-0", "1alpha.0", 0],
          ["1alpha-0", "1alpha.z", -1],

          ["1beta-0", "1beta", 0],
          ["1beta-0", "1beta0", 0],
          ["1beta-0", "1beta.0", 0],
          ["1beta-0", "1beta.z", -1],

          ["1rc-0", "1rc0", 0],
          ["1rc-0", "1rc", 0],
          ["1rc-0", "1rc.0", 0],
          ["1rc-0", "1rc.z", -1],

          ["1sp-0", "1sp0", 0],
          ["1sp-0", "1sp", 0],
          ["1sp-0", "1sp.0", 0],
          ["1sp-0", "1sp.z", -1],

          ["1.ga", "1-ga", 0],
          ["1.0", "1.ga", 0],
          ["1.0.FINAL", "1", 0],
          ["1.0", "1.release", 0],

          ["1.2.0", "1.2", 0],
          ["1.2.3", "1.2.3-0", 0],
          ["1.2.3-0", "1.2.3-0", 0],
          ["1.2.3-0", "1.2.3-a0", 1],
          ["1.2.3-0", "1.2.3-a", -1],
          ["1.2.3-0", "1.2.3-1", -1],
          ["1.2.3-0", "1.2.3-0-1", -1],

          ["1snapshot-0", "1snapshot0", 0],
          ["1snapshot-0", "1snapshot", 0],
          ["1snapshot-0", "1snapshot.0", 0],
          ["1snapshot-0", "1snapshot.z", -1],

          ["1milestone-0", "1milestone", 0],
          ["1milestone-0", "1milestone0", 0],
          ["1milestone-0", "1milestone.0", 0],
          ["1milestone-0", "1milestone.z", -1]
        ]
      end

      it "returns the correct result" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "with equivalent shortened qualifiers" do
      let(:versions) do
        [
          ["1alpha-0", "1a0", 0],
          ["1beta-0", "1b0", 0],
          ["1milestone-0", "1m0", 0]
        ]
      end

      it "returns 0" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "with dot, hyphen and digit / qualifier transitions as separators" do
      let(:versions) do
        [
          ["1alpha.z", "1alpha-z", 0],
          ["1alpha1", "1alpha-1", 0],
          ["1alpha-1", "1alpha.1", -1],
          ["1beta.z", "1beta-z", 0],
          ["1beta1", "1beta-1", 0],
          ["1beta-1", "1beta.1", -1],
          ["1-a", "1a", 0],
          ["1-a", "1.a", 0],
          ["1-b", "1-b-1", -1],
          ["1-b-1", "1-b.1", -1],
          ["1sp.z", "1sp-z", 0],
          ["1sp1", "1sp-1", 0],
          ["1sp-1", "1sp.1", -1],
          ["1rc.z", "1rc-z", 0],
          ["1rc1", "1rc-1", 0],
          ["1rc-1", "1rc.1", -1],
          ["1milestone.z", "1milestone-z", 0],
          ["1milestone1", "1milestone-1", 0],
          ["1milestone-1", "1milestone.1", -1],
          ["1snapshot.z", "1snapshot-z", 0],
          ["1snapshot1", "1snapshot-1", 0],
          ["1snapshot-1", "1snapshot.1", -1]
        ]
      end

      it "returns 0" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "with qualifiers with different precedence" do
      let(:versions) do
        [
          ["1alpha.1", "1beta.1", -1],
          ["1beta.1", "1milestone.1", -1],
          ["1milestone.1", "1rc.1", -1],
          ["1rc.1", "1snapshot.1", -1],
          ["1.sp", "1.ga", 1],
          ["1.release", "1.ga", 0]
        ]
      end

      it "returns the correct value" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "with equivalent qualifiers cr and rc" do
      let(:version) { described_class.new("1.0rc-1") }
      let(:other_version) { described_class.new("1.0-cr1") }

      it "returns 0" do
        expect(version <=> other_version).to eq(0)
        expect(other_version <=> version).to eq(0)
      end
    end

    context "when comparing alphanumerically" do
      let(:versions) do
        [
          ["1alpha-z", "1alpha1", -1],
          ["1beta-z", "1beta1", -1],
          ["1milestone-z", "1milestone1", -1],
          ["1rc-z", "1rc1", -1],
          ["1snapshot-z", "1snapshot1", -1],
          ["1sp-z", "1sp1", -1],
          ["181", "DEV", 1]
        ]
      end

      it "gives higher precedence to digits" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "when comparing alphabetically" do
      let(:versions) do
        [
          ["1-a", "1-b", -1],
          ["Finchley", "Edgware", 1],
          ["1.something", "1.SOMETHING", 0]
        ]
      end

      it "returns the correct result" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "when comparing numerically" do
      let(:versions) do
        [
          ["1-b.1", "1-b.2", -1],
          ["9.0.0+102", "9.0.0+91", 1],
          ["1-foo2", "1-foo10", -1]

        ]
      end

      it "returns the correct result" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "when comparing padded versions" do
      let(:versions) do
        [
          ["1snapshot.1", "1", -1],
          ["1-snapshot", "1", -1],
          ["1", "1sp0", -1],
          ["1sp.1", "1-a", -1],
          ["1", "1.1", -1],
          ["1", "1-sp", -1],
          ["1-ga-1", "1-1", -1]
        ]
      end

      it "returns the correct result" do
        versions.each do |input|
          version1, version2, result = input
          version = described_class.new(version1)
          other_version = described_class.new(version2)
          expect(version <=> other_version).to eq(result)
          expect(other_version <=> version).to eq(-result)
        end
      end
    end

    context "when ordering versions" do
      let(:versions) do
        [
          described_class.new("NotAVersionSting"),
          described_class.new("1.0-alpha"),
          described_class.new("1.0a1-SNAPSHOT"),
          described_class.new("1.0-alpha1"),
          described_class.new("1.0beta1-SNAPSHOT"),
          described_class.new("1.0-b2"),
          described_class.new("1.0-beta3.SNAPSHOT"),
          described_class.new("1.0-beta3"),
          described_class.new("1.0-milestone1-SNAPSHOT"),
          described_class.new("1.0-m2"),
          described_class.new("1.0-rc1-SNAPSHOT"),
          described_class.new("1.0-cr1"),
          described_class.new("1.0-SNAPSHOT"),
          described_class.new("1.0-RELEASE"),
          described_class.new("1.0-sp"),
          described_class.new("1.0-a"),
          described_class.new("1.0-whatever"),
          described_class.new("1.0.z"),
          described_class.new("1.0.1"),
          described_class.new("1.0.1.0.0.0.0.0.0.0.0.0.0.0.1")
        ]
      end

      it "sorts versions correctly" do
        expect(versions.shuffle.sort).to eq(versions)
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

    context "with an invalid version" do
      let(:version_string) { "0.9.0" }

      it { is_expected.to be(false) }
    end

    context "with a valid dash-separated version" do
      let(:version_string) { "1.1.0-pre" }

      it { is_expected.to be(true) }
    end
  end
end
