# frozen_string_literal: true

# require "spec_helper"
require "dependabot/haskell/version"

RSpec.describe Dependabot::Haskell::Version do
  subject(:version) { described_class.new(version_string) }
  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a string prefixed with a 'v'" do
      let(:version_string) { "v1.0.0" }
      it { is_expected.to eq(false) }
    end

    context "with a string not prefixed with a 'v'" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(true) }
    end

    context "with an 'incompatible' suffix" do
      let(:version_string) { "v1.0.0+incompatible" }
      it { is_expected.to eq(false) }
    end

    context "with an invalid string" do
      let(:version_string) { "va1.0.0" }
      it { is_expected.to eq(false) }
    end

  end

  describe "#to_s" do
    subject { version.to_s }

    context "with a PVP version" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq "1.0.0" }
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
  end
end
