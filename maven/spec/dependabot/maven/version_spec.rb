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
      it { is_expected.to eq(true) }
    end

    context "with a normal version" do
      let(:version_string) { "Finchley" }
      it { is_expected.to eq(true) }
    end

    context "with a dynamic version" do
      let(:version_string) { "1.+" }
      it { is_expected.to eq(true) }
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
  end

  describe "#prerelease?" do
    subject { version.prerelease? }

    context "with an alpha" do
      let(:version_string) { "1.0.0-alpha" }
      it { is_expected.to eq(true) }
    end

    context "with a capitalised alpha" do
      let(:version_string) { "1.0.0-Alpha" }
      it { is_expected.to eq(true) }
    end

    context "with an alpha separated with a ." do
      let(:version_string) { "1.0.0.alpha" }
      it { is_expected.to eq(true) }
    end

    context "with an alpha with no separator" do
      let(:version_string) { "1.0.0alpha" }
      it { is_expected.to eq(true) }
    end

    context "with an alligator" do
      let(:version_string) { "1.0.0alligator" }
      it { is_expected.to eq(false) }
    end

    context "with a release" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(false) }
    end

    context "with a post-release" do
      let(:version_string) { "1.0.0.sp7" }
      it { is_expected.to eq(false) }
    end

    context "with a pre-release" do
      let(:version_string) { "2.10.0.pr3" }
      it { is_expected.to eq(true) }
    end

    context "with a dev token" do
      let(:version_string) { "1.2.1-dev-65" }
      it { is_expected.to eq(true) }
    end
  end

  describe "#<=>" do
    subject { version.send(:<=>, other_version) }

    context "compared to a Gem::Version" do
      context "that is lower" do
        let(:other_version) { Gem::Version.new("0.9.0") }
        it { is_expected.to eq(1) }
      end

      context "that is equal" do
        let(:other_version) { Gem::Version.new("1.0.0") }
        it { is_expected.to eq(0) }
      end

      context "that is greater" do
        let(:other_version) { Gem::Version.new("1.1.0") }
        it { is_expected.to eq(-1) }
      end
    end

    context "compared to a Maven::Version" do
      context "that is lower" do
        let(:other_version) { described_class.new("0.9.0") }
        it { is_expected.to eq(1) }
      end

      context "that is equal" do
        let(:other_version) { described_class.new("1.0.0") }
        it { is_expected.to eq(0) }

        context "but prefixed with a v" do
          let(:other_version) { described_class.new("v1.0.0") }
          it { is_expected.to eq(0) }
        end

        context "using different date formats" do
          let(:version_string) { "20181003" }
          let(:other_version) { described_class.new("v2018-10-03") }
          it { is_expected.to eq(0) }
        end
      end

      context "that is greater" do
        let(:other_version) { described_class.new("1.1.0") }
        it { is_expected.to eq(-1) }
      end

      context "that is a post-release" do
        let(:other_version) { described_class.new("1.0.0u1") }
        it { is_expected.to eq(-1) }
      end

      context "that is a pre-release" do
        let(:other_version) { described_class.new("1.0.0a1") }
        it { is_expected.to eq(1) }
      end

      context "that is non-numeric" do
        let(:version) { described_class.new("Finchley") }
        let(:other_version) { described_class.new("Edgware") }
        it { is_expected.to eq(1) }
      end

      describe "with a + separated alphanumeric build identifier" do
        context "that is equal" do
          let(:version_string) { "9.0.0+100" }
          let(:other_version) { described_class.new("9.0.0+100") }
          it { is_expected.to eq(0) }
        end

        context "that is greater" do
          let(:version_string) { "9.0.0+102" }
          let(:other_version) { described_class.new("9.0.0+101") }
          it { is_expected.to eq(1) }
        end

        context "that is less than" do
          let(:version_string) { "9.0.0+100" }
          let(:other_version) { described_class.new("9.0.0+101") }
          it { is_expected.to eq(-1) }
        end
      end

      describe "from the spec" do
        context "number padding" do
          let(:version) { described_class.new("1") }
          let(:other_version) { described_class.new("1.1") }
          it { is_expected.to eq(-1) }
        end

        context "qualifier padding" do
          let(:version) { described_class.new("1-snapshot") }
          let(:other_version) { described_class.new("1") }
          it { is_expected.to eq(-1) }
        end

        context "qualifier padding 1" do
          let(:version) { described_class.new("1") }
          let(:other_version) { described_class.new("1-sp") }
          it { is_expected.to eq(-1) }
        end

        context "switching" do
          let(:version) { described_class.new("1-foo2") }
          let(:other_version) { described_class.new("1-foo10") }
          it { is_expected.to eq(-1) }
        end

        context "prefixes" do
          let(:version) { described_class.new("1.foo") }
          let(:other_version) { described_class.new("1-foo") }
          it { is_expected.to eq(-1) }
        end

        context "prefixes2" do
          let(:version) { described_class.new("1-foo") }
          let(:other_version) { described_class.new("1-1") }
          it { is_expected.to eq(-1) }
        end

        context "prefixes3" do
          let(:version) { described_class.new("1-1") }
          let(:other_version) { described_class.new("1.1") }
          it { is_expected.to eq(-1) }
        end

        context "null values" do
          let(:version) { described_class.new("1.ga") }
          let(:other_version) { described_class.new("1-ga") }
          it { is_expected.to eq(0) }
        end

        context "null values 2" do
          let(:version) { described_class.new("1-ga") }
          let(:other_version) { described_class.new("1-0") }
          it { is_expected.to eq(0) }
        end

        context "null values 3" do
          let(:version) { described_class.new("1-0") }
          let(:other_version) { described_class.new("1.0") }
          it { is_expected.to eq(0) }
        end

        context "null values 4" do
          let(:version) { described_class.new("1.0") }
          let(:other_version) { described_class.new("1") }
          it { is_expected.to eq(0) }
        end

        context "null values 5" do
          let(:version) { described_class.new("1.0.") }
          let(:other_version) { described_class.new("1") }
          it { is_expected.to eq(0) }
        end

        context "null values 6" do
          let(:version) { described_class.new("1.0-.2") }
          let(:other_version) { described_class.new("1.0-0.2") }
          it { is_expected.to eq(0) }
        end

        context "case insensitivity" do
          let(:version) { described_class.new("1.0.FINAL") }
          let(:other_version) { described_class.new("1") }
          it { is_expected.to eq(0) }
        end

        context "case insensitivity 2" do
          let(:version) { described_class.new("1.something") }
          let(:other_version) { described_class.new("1.SOMETHING") }
          it { is_expected.to eq(0) }
        end

        context "post releases" do
          let(:version) { described_class.new("1-sp") }
          let(:other_version) { described_class.new("1-ga") }
          it { is_expected.to eq(1) }
        end

        context "post releases 2" do
          let(:version) { described_class.new("1-sp.1") }
          let(:other_version) { described_class.new("1-ga.1") }
          it { is_expected.to eq(1) }
        end

        context "null values (again)" do
          let(:version) { described_class.new("1-sp-1") }
          let(:other_version) { described_class.new("1-ga-1") }
          it { is_expected.to eq(-1) }
        end

        context "null values (again 2)" do
          let(:version) { described_class.new("1-ga-1") }
          let(:other_version) { described_class.new("1-1") }
          it { is_expected.to eq(0) }
        end

        context "named values" do
          let(:version) { described_class.new("1-a1") }
          let(:other_version) { described_class.new("1-alpha-1") }
          it { is_expected.to eq(0) }
        end

        context "comparing string versions with integer ones" do
          let(:version) { described_class.new("181") }
          let(:other_version) { described_class.new("dev") }
          it { is_expected.to eq(1) }
        end
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

    context "with a valid dash-separated version" do
      let(:version_string) { "1.1.0-pre" }
      it { is_expected.to eq(true) }
    end
  end
end
