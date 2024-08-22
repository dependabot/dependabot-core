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

    context "with a 'pr' pre-release separated with a ." do
      let(:version_string) { "2.10.0.pr3" }

      it { is_expected.to be(true) }
    end

    context "with a 'pre' pre-release separated with a -" do
      let(:version_string) { "2.10.0-pre0" }

      it { is_expected.to be(true) }
    end

    context "with a dev token" do
      let(:version_string) { "1.2.1-dev-65" }

      it { is_expected.to be(true) }
    end
  end

  describe "#<=>" do
    subject { version.send(:<=>, other_version) }

    context "when comparing to a Maven::Version" do
      context "when lower" do
        let(:other_version) { described_class.new("0.9.0") }

        it { is_expected.to eq(1) }
      end

      context "when equal" do
        let(:other_version) { described_class.new("1.0.0") }

        it { is_expected.to eq(0) }

        context "when prefixed with a v" do
          let(:other_version) { described_class.new("v1.0.0") }

          it { is_expected.to eq(0) }
        end

        context "when using different date formats" do
          let(:version_string) { "20181003" }
          let(:other_version) { described_class.new("v2018-10-03") }

          it { is_expected.to eq(0) }
        end
      end

      context "when greater" do
        let(:other_version) { described_class.new("1.1.0") }

        it { is_expected.to eq(-1) }
      end

      context "when the version is a post-release" do
        let(:other_version) { described_class.new("1.0.0u1") }

        it { is_expected.to eq(-1) }
      end

      context "when the version is a pre-release" do
        let(:other_version) { described_class.new("1.0.0a1") }

        it { is_expected.to eq(1) }
      end

      context "when the version is non-numeric" do
        let(:version) { described_class.new("Finchley") }
        let(:other_version) { described_class.new("Edgware") }

        it { is_expected.to eq(1) }
      end

      describe "with a + separated alphanumeric build identifier" do
        context "when equal" do
          let(:version_string) { "9.0.0+100" }
          let(:other_version) { described_class.new("9.0.0+100") }

          it { is_expected.to eq(0) }
        end

        context "when greater" do
          let(:version_string) { "9.0.0+102" }
          let(:other_version) { described_class.new("9.0.0+101") }

          it { is_expected.to eq(1) }
        end

        context "when less than" do
          let(:version_string) { "9.0.0+100" }
          let(:other_version) { described_class.new("9.0.0+101") }

          it { is_expected.to eq(-1) }
        end
      end

      describe "from the spec" do
        context "when dealing with number padding" do
          let(:version) { described_class.new("1") }
          let(:other_version) { described_class.new("1.1") }

          it { is_expected.to eq(-1) }
        end

        context "when dealing with qualifier padding" do
          let(:version) { described_class.new("1-snapshot") }
          let(:other_version) { described_class.new("1") }

          it { is_expected.to eq(-1) }
        end

        context "when dealing with qualifier padding 1" do
          let(:version) { described_class.new("1") }
          let(:other_version) { described_class.new("1-sp") }

          it { is_expected.to eq(-1) }
        end

        context "when dealing with switching" do
          let(:version) { described_class.new("1-foo2") }
          let(:other_version) { described_class.new("1-foo10") }

          it { is_expected.to eq(-1) }
        end

        context "when dealing with prefixes" do
          let(:version) { described_class.new("1.foo") }
          let(:other_version) { described_class.new("1-foo") }

          it { is_expected.to eq(-1) }
        end

        context "when dealing with prefixes2" do
          let(:version) { described_class.new("1-foo") }
          let(:other_version) { described_class.new("1-1") }

          it { is_expected.to eq(-1) }
        end

        context "when dealing with prefixes3" do
          let(:version) { described_class.new("1-1") }
          let(:other_version) { described_class.new("1.1") }

          it { is_expected.to eq(-1) }
        end

        context "when dealing with null values" do
          let(:version) { described_class.new("1.ga") }
          let(:other_version) { described_class.new("1-ga") }

          it { is_expected.to eq(0) }
        end

        context "when dealing with null values 2" do
          let(:version) { described_class.new("1-ga") }
          let(:other_version) { described_class.new("1-0") }

          it { is_expected.to eq(0) }
        end

        context "when dealing with null values 3" do
          let(:version) { described_class.new("1-0") }
          let(:other_version) { described_class.new("1.0") }

          it { is_expected.to eq(0) }
        end

        context "when dealing with null values 4" do
          let(:version) { described_class.new("1.0") }
          let(:other_version) { described_class.new("1") }

          it { is_expected.to eq(0) }
        end

        context "when dealing with null values 5" do
          let(:version) { described_class.new("1.0.") }
          let(:other_version) { described_class.new("1") }

          it { is_expected.to eq(0) }
        end

        context "when dealing with null values 6" do
          let(:version) { described_class.new("1.0-.2") }
          let(:other_version) { described_class.new("1.0-0.2") }

          it { is_expected.to eq(0) }
        end

        context "when dealing with case insensitivity" do
          let(:version) { described_class.new("1.0.FINAL") }
          let(:other_version) { described_class.new("1") }

          it { is_expected.to eq(0) }
        end

        context "when dealing with case insensitivity 2" do
          let(:version) { described_class.new("1.something") }
          let(:other_version) { described_class.new("1.SOMETHING") }

          it { is_expected.to eq(0) }
        end

        context "when dealing with post releases" do
          let(:version) { described_class.new("1-sp") }
          let(:other_version) { described_class.new("1-ga") }

          it { is_expected.to eq(1) }
        end

        context "when dealing with post releases 2" do
          let(:version) { described_class.new("1-sp.1") }
          let(:other_version) { described_class.new("1-ga.1") }

          it { is_expected.to eq(1) }
        end

        # this looks incorrect https://maven.apache.org/pom.html#Version_Order_Specification
        context "when dealing with null values (again)" do
          let(:version) { described_class.new("1-sp-1") }
          let(:other_version) { described_class.new("1-ga-1") }

          it { is_expected.to eq(-1) }
        end

        context "when dealing with null values (again 2)" do
          let(:version) { described_class.new("1-ga-1") }
          let(:other_version) { described_class.new("1-1") }

          it { is_expected.to eq(0) }
        end

        context "when dealing with named values" do
          let(:versions) do
            [
              { version: "1-a1", other_version: "1-alpha-1" },
              { version: "1.0-beta1", other_version: "1.0-b1" },
              { version: "1.0-milestone1", other_version: "1.0-m1" },
              { version: "1.0-rc1", other_version: "1.0-cr1" }
            ]
          end

          it "returns 0 for all equivalent versions" do
            versions.each do |v|
              version = described_class.new(v[:version])
              other_version = described_class.new(v[:other_version])
              expect(version <=> other_version).to eq 0
            end
          end
        end

        context "when comparing string versions with integer ones" do
          let(:version) { described_class.new("181") }
          let(:other_version) { described_class.new("dev") }

          it { is_expected.to eq(1) }
        end

        context "with equivalent separators" do
          let(:versions) do
            [
              { version: "1.0alpha1", other_version: "1.0-a1" },
              { version: "1.0beta-1", other_version: "1.0-b1" },
              { version: "1.0milestone1", other_version: "1.0-m1" },
              { version: "1.0milestone-1", other_version: "1.0-m1" },
              { version: "1.0rc-1", other_version: "1.0-cr1" },
              { version: "1.0rc1", other_version: "1.0-cr1" },
              { version: "1.0ga", other_version: "1.0" },
              { version: "1-0.ga", other_version: "1.0" },
              { version: "1.0-final", other_version: "1.0" },
              { version: "1-0-ga", other_version: "1.0" },
              { version: "1-0-final", other_version: "1-0" },
              { version: "1-0", other_version: "1.0" }
            ]
          end

          it "returns 0 for all equivalent versions" do
            versions.each do |v|
              version = described_class.new(v[:version])
              other_version = described_class.new(v[:other_version])
              expect(version <=> other_version).to eq 0
            end
          end
        end

        context "with unequal separators" do
          let(:version) { described_class.new("1.0alpha.1") }
          let(:other_version) { described_class.new("1.0-a1") }

          it { is_expected.to eq(1) }
        end

        context "with long versions" do
          let(:versions) do
            [{
              version: "1.0.0.0.0.0.0",
              other_version: "1"
            }, {
              version: "1.0.0.0.0.0.0x",
              other_version: "1x"
            }]
          end

          it "returns 0 for equivalent versions" do
            versions.each do |v|
              version = described_class.new(v[:version])
              other_version = described_class.new(v[:other_version])
              expect(version <=> other_version).to eq 0
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
              described_class.new("1.0"),
              described_class.new("1.0-sp"),
              # described_class.new("1.0-a"),
              described_class.new("1.0-RELEASE"),
              described_class.new("1.0-whatever"),
              # described_class.new("1.0.z"),
              described_class.new("1.0.1"),
              described_class.new("1.0.1.0.0.0.0.0.0.0.0.0.0.0.1")
            ]
          end

          it "sorts versions based on the maven specification" do
            expect(versions.shuffle.sort).to eq(versions)
          end
        end
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
