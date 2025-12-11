# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/crystal_shards/version"

RSpec.describe Dependabot::CrystalShards::Version do
  describe ".new" do
    subject(:version) { described_class.new(version_string) }

    context "with a standard version" do
      let(:version_string) { "1.2.3" }

      it { is_expected.to eq(described_class.new("1.2.3")) }
    end

    context "with a pre-release version" do
      let(:version_string) { "1.0.0-alpha" }

      it { is_expected.to eq(described_class.new("1.0.0-alpha")) }
    end
  end

  describe "#<=>" do
    it "correctly compares versions" do
      expect(described_class.new("1.0.0")).to be < described_class.new("2.0.0")
      expect(described_class.new("1.0.0")).to be < described_class.new("1.1.0")
      expect(described_class.new("1.0.0")).to be < described_class.new("1.0.1")
    end

    it "recognizes equal versions" do
      version_a = described_class.new("1.0.0")
      version_b = described_class.new("1.0.0")
      expect(version_a).to eq(version_b)
    end

    it "handles pre-release versions" do
      expect(described_class.new("1.0.0-alpha")).to be < described_class.new("1.0.0")
      expect(described_class.new("1.0.0-alpha")).to be < described_class.new("1.0.0-beta")
    end
  end

  describe "#to_s" do
    subject { described_class.new(version_string).to_s }

    let(:version_string) { "1.2.3" }

    it { is_expected.to eq("1.2.3") }
  end
end
