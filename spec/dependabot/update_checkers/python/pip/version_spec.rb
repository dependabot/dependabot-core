# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/python/pip/version"

RSpec.describe Dependabot::UpdateCheckers::Python::Pip::Version do
  subject(:version) { described_class.new(version_string) }
  let(:version_string) { "1.0.0" }

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
    subject { version <=> other_version }

    context "compared to a Gem::Version" do
      context "that is lower" do
        let(:other_version) { Gem::Version.new("0.9.0") }
        it { is_expected.to eq(1) }
      end

      context "that is equal" do
        let(:other_version) { Gem::Version.new("1.0.0") }
        it { is_expected.to eq(0) }

        context "but our version has a local version" do
          let(:version_string) { "1.0.0+gc.1" }
          it { is_expected.to eq(1) }
        end
      end

      context "that is greater" do
        let(:other_version) { Gem::Version.new("1.1.0") }
        it { is_expected.to eq(-1) }
      end
    end

    context "compared to a Pip::Version" do
      context "that is lower" do
        let(:other_version) { described_class.new("0.9.0") }
        it { is_expected.to eq(1) }
      end

      context "that is equal" do
        let(:other_version) { described_class.new("1.0.0") }
        it { is_expected.to eq(0) }

        context "but our version has a local version" do
          let(:version_string) { "1.0.0+gc.1" }
          it { is_expected.to eq(1) }
        end

        context "but the other version has a local version" do
          let(:other_version) { described_class.new("1.0.0+gc.1") }
          it { is_expected.to eq(-1) }
        end

        context "and both sides have a local version" do
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
