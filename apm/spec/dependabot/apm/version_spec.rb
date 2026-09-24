# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/apm/version"

RSpec.describe Dependabot::Apm::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.2.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a plain semver string" do
      let(:version_string) { "1.2.0" }

      it { is_expected.to be(true) }
    end

    context "with a leading v" do
      let(:version_string) { "v1.2.0" }

      it { is_expected.to be(true) }
    end

    context "with a branch name" do
      let(:version_string) { "main" }

      it { is_expected.to be(false) }
    end

    context "with a commit SHA" do
      let(:version_string) { "0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e" }

      it { is_expected.to be(false) }
    end

    context "with an empty string" do
      let(:version_string) { "" }

      it { is_expected.to be(false) }
    end

    context "with nil" do
      let(:version_string) { nil }

      it { is_expected.to be(false) }
    end
  end

  describe "#initialize" do
    context "with a leading v" do
      let(:version_string) { "v1.2.0" }

      it "strips the v and compares equal to the plain version" do
        expect(version).to eq(described_class.new("1.2.0"))
        expect(version.to_s).to eq("1.2.0")
      end
    end

    context "without a leading v" do
      let(:version_string) { "1.2.0" }

      it "keeps the version as-is" do
        expect(version.to_s).to eq("1.2.0")
      end
    end
  end

  describe "comparison" do
    it "orders versions numerically regardless of a leading v" do
      expect(described_class.new("v1.10.0")).to be > described_class.new("1.9.0")
      expect(described_class.new("1.0.0")).to be < described_class.new("v2.0.0")
    end
  end
end
