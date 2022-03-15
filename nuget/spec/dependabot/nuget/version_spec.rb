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
      it { is_expected.to eq "1.0.0+gc.1" }
    end

    context "with a blank version" do
      let(:version_string) { "" }
      it { is_expected.to eq "" }
    end

    context "with pre-release details" do
      let(:version_string) { "1.0.0-beta+abc.1" }
      it { is_expected.to eq("1.0.0-beta+abc.1") }
    end
  end

  describe "#<=>" do
    subject { version <=> other_version }

    context "compared to a Gem::Version" do
      context "that is lower" do
        let(:other_version) { Gem::Version.new("0.9.0") }
        it { is_expected.to eq(1) }
      end

      context "that is equal" do
        let(:other_version) { Gem::Version.new("1.0.0") }
        it { is_expected.to eq(0) }

        context "but our version has build information" do
          let(:version_string) { "1.0.0+gc.1" }
          it { is_expected.to eq(1) }
        end
      end

      context "that is greater" do
        let(:other_version) { Gem::Version.new("1.1.0") }
        it { is_expected.to eq(-1) }
      end
    end

    context "compared to a Nuget::Version" do
      context "that is lower" do
        let(:other_version) { described_class.new("0.9.0") }
        it { is_expected.to eq(1) }
      end

      context "that is equal" do
        let(:other_version) { described_class.new("1.0.0") }
        it { is_expected.to eq(0) }

        context "and both versions are blank" do
          let(:other_version) { described_class.new("") }
          let(:version_string) { described_class.new("") }
          it { is_expected.to eq(0) }
        end

        context "but our version has build information" do
          let(:version_string) { "1.0.0+gc.1" }
          it { is_expected.to eq(1) }
        end

        context "but the other version has build information" do
          let(:other_version) { described_class.new("1.0.0+gc.1") }
          it { is_expected.to eq(-1) }
        end

        context "and both sides have build information" do
          let(:other_version) { described_class.new("1.0.0+gc.1") }

          context "that is equal" do
            let(:version_string) { "1.0.0+gc.1" }
            it { is_expected.to eq(0) }
          end

          context "when our side is greater" do
            let(:version_string) { "1.0.0+gc.2" }
            it { is_expected.to eq(1) }
          end

          context "when our side is lower" do
            let(:version_string) { "1.0.0+gc" }
            it { is_expected.to eq(-1) }
          end

          context "when our side is longer" do
            let(:version_string) { "1.0.0+gc.1.1" }
            it { is_expected.to eq(1) }
          end
        end
      end

      context "that is greater" do
        let(:other_version) { described_class.new("1.1.0") }
        it { is_expected.to eq(-1) }

        context "and this version is a blank version" do
          let(:version_string) { described_class.new("") }
          it { is_expected.to eq(-1) }
        end

        context "with an easy pre-release" do
          let(:version_string) { "3.0.0-alpha" }
          let(:other_version) { "3.0.0-beta" }

          it { is_expected.to eq(-1) }
        end

        context "with a not-so-easy pre-release" do
          let(:version_string) { "3.0.0-alpha" }
          let(:other_version) { "3.0.0-alpha2" }

          it { is_expected.to eq(-1) }
        end

        context "with a tricky pre-release" do
          let(:version_string) { "3.0.0-preview.19108.1" }
          let(:other_version) { "3.0.0-preview7.19362.4" }

          it { is_expected.to eq(-1) }
        end
      end

      context "that is a blank version" do
        let(:other_version) { described_class.new("") }
        it { is_expected.to eq(1) }
      end

      context "that has pre-release identifiers" do
        context "with one version having a longer dot-separated prerelease identifier" do
          let(:version_string) { "3.2.0-alpha.1" }
          let(:other_version) { "3.2.0-alpha" }

          it { is_expected.to eq(1) }
        end

        context "with one that is lexically shorter" do
          let(:version_string) { "3.2.0-alpha0014" }
          let(:other_version) { "3.2.0-alpha.66" } # the .66 doesn't matter because alpha < alpha0014 lexically

          it { is_expected.to eq(1) }
        end

        context "with a dot separated identifier containing integers" do
          let(:version_string) { "1.3.1-preview.8" }
          let(:other_version) { "1.3.1-preview.24" }

          it { is_expected.to eq(-1) }
        end

        context "with a longer dot separated identifier containing integers" do
          let(:version_string) { "1.3.1-preview.8.2" }
          let(:other_version) { "1.3.1-preview.8.1" }

          it { is_expected.to eq(1) }
        end

        context "with equal dot separated integers" do
          let(:version_string) { "1.3.1-preview.8.2" }
          let(:other_version) { "1.3.1-preview.8.2" }

          it { is_expected.to eq(0) }
        end

        context "with pre-release does not take precedence over non-pre-release" do
          let(:version_string) { "1.0.0" }
          let(:other_version) { "1.0.0-alpha" }

          it { is_expected.to eq(1) }
        end

        context "with numeric taking lower precedence than non-numeric" do
          let(:version_string) { "1.0.0-1" }
          let(:other_version) { "1.0.0-alpha" }

          it { is_expected.to eq(-1) }
        end

        context "with a pre-release identifier containing hyphens" do
          let(:version_string) { "1.0.0-1" }
          let(:other_version) { "1.0.0-1-1" }

          it { is_expected.to eq(-1) }
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

    context "with a valid build information" do
      let(:version_string) { "1.1.0+gc.1" }
      it { is_expected.to eq(true) }
    end
  end
end
