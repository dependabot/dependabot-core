# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/elm/version"

RSpec.describe Dependabot::Elm::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with nil" do
      let(:version_string) { nil }

      it { is_expected.to be(false) }
    end

    context "with an invalid version" do
      let(:version_string) { "1.0.0a" }

      it { is_expected.to be(false) }
    end
  end

  describe "#to_s" do
    subject { version.to_s }

    context "with a valid string" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to eq "1.0.0" }
    end
  end

  describe "#<=>" do
    subject { version <=> other_version }

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
  end
end
