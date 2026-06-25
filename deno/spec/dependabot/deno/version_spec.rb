# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/version"

RSpec.describe Dependabot::Deno::Version do
  subject(:version) { described_class.new(version_string) }

  describe ".correct?" do
    it "returns true for standard semver" do
      expect(described_class.correct?("1.2.3")).to be true
    end

    it "returns true for pre-release" do
      expect(described_class.correct?("1.0.0-rc.1")).to be true
    end

    it "returns true for build metadata" do
      expect(described_class.correct?("1.0.0+build.1")).to be true
    end

    it "returns false for nil" do
      expect(described_class.correct?(nil)).to be false
    end

    it "returns false for garbage" do
      expect(described_class.correct?("not-a-version")).to be false
    end
  end

  describe "#to_s" do
    let(:version_string) { "1.2.3" }

    it "preserves the original string" do
      expect(version.to_s).to eq("1.2.3")
    end

    context "with build info" do
      let(:version_string) { "1.0.0+build.1" }

      it "preserves build metadata" do
        expect(version.to_s).to eq("1.0.0+build.1")
      end
    end
  end

  describe "#build_info" do
    context "with build metadata" do
      let(:version_string) { "1.0.0+20230101" }

      it "extracts build info" do
        expect(version.build_info).to eq("20230101")
      end
    end

    context "without build metadata" do
      let(:version_string) { "1.0.0" }

      it "returns nil" do
        expect(version.build_info).to be_nil
      end
    end
  end

  describe "comparison" do
    it "sorts versions correctly" do
      versions = %w(1.0.0 2.0.0 1.1.0 1.0.1).map { |v| described_class.new(v) }
      expect(versions.sort.map(&:to_s)).to eq(%w(1.0.0 1.0.1 1.1.0 2.0.0))
    end
  end
end
