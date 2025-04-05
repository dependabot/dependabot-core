# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex/version"

RSpec.describe Dependabot::Hex::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }

      context "when our version includes build information" do
        let(:version_string) { "1.0.0+abc.1" }

        it { is_expected.to be(true) }
      end

      context "when our version includes pre-release details" do
        let(:version_string) { "1.0.0-beta+abc.1" }

        it { is_expected.to be(true) }
      end
    end

    context "with nil" do
      let(:version_string) { nil }

      it { is_expected.to be(false) }
    end

    context "with a blank version" do
      let(:version_string) { "" }

      it { is_expected.to be(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "bad" }

      it { is_expected.to be(false) }

      context "when our version includes build information" do
        let(:version_string) { "1.0.0+abc 123" }

        it { is_expected.to be(false) }
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

    context "when comparing our version to a Gem::Version" do
      context "when our version is lower" do
        let(:other_version) { Gem::Version.new("0.9.0") }

        it { is_expected.to eq(1) }
      end

      context "when our version is equal" do
        let(:other_version) { Gem::Version.new("1.0.0") }

        it { is_expected.to eq(0) }

        context "when our version has build information" do
          let(:version_string) { "1.0.0+gc.1" }

          it { is_expected.to eq(1) }
        end
      end

      context "when our version is greater" do
        let(:other_version) { Gem::Version.new("1.1.0") }

        it { is_expected.to eq(-1) }
      end
    end

    context "when comparing our version to a Hex::Version" do
      context "when our version is lower" do
        let(:other_version) { described_class.new("0.9.0") }

        it { is_expected.to eq(1) }
      end

      context "when our version is equal" do
        let(:other_version) { described_class.new("1.0.0") }

        it { is_expected.to eq(0) }

        context "when our version has build information" do
          let(:version_string) { "1.0.0+gc.1" }

          it { is_expected.to eq(1) }
        end

        context "when the other version has build information" do
          let(:other_version) { described_class.new("1.0.0+gc.1") }

          it { is_expected.to eq(-1) }
        end

        context "when both sides have build information" do
          let(:other_version) { described_class.new("1.0.0+gc.1") }

          context "when the version is equal" do
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

      context "when our version is greater" do
        let(:other_version) { described_class.new("1.1.0") }

        it { is_expected.to eq(-1) }
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

    context "with a valid build information" do
      let(:version_string) { "1.1.0+gc.1" }

      it { is_expected.to be(true) }
    end
  end
end
