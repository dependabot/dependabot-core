# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/opam/version"

RSpec.describe Dependabot::Opam::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with a pre-release version" do
      let(:version_string) { "1.0~beta" }

      it { is_expected.to be(true) }
    end

    context "with a dev version" do
      let(:version_string) { "dev" }

      it { is_expected.to be(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "bad version!" }

      it { is_expected.to be(false) }
    end
  end

  describe "#<=>" do
    subject { version <=> other_version }

    context "when comparing equal versions" do
      let(:other_version) { described_class.new("1.0.0") }

      it { is_expected.to eq(0) }
    end

    context "when comparing different versions" do
      let(:version_string) { "1.0.1" }
      let(:other_version) { described_class.new("1.0.0") }

      it { is_expected.to eq(1) }
    end

    context "with pre-release versions" do
      let(:version_string) { "1.0~beta" }
      let(:other_version) { described_class.new("1.0") }

      it "pre-release is less than release" do
        expect(version).to be < other_version
      end
    end

    context "with tilde ordering" do
      let(:version_string) { "1.0~beta2" }
      let(:other_version) { described_class.new("1.0~beta10") }

      it { is_expected.to eq(-1) }
    end
  end

  describe "#to_semver" do
    subject { version.to_semver }

    context "with a standard version" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to eq("1.0.0") }
    end

    context "with a pre-release version" do
      let(:version_string) { "1.0~beta" }

      it { is_expected.to eq("1.0-beta") }
    end
  end
end
