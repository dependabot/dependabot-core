# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/devbox/version"

RSpec.describe Dependabot::Devbox::Version do
  subject(:version) { described_class.new(version_string) }

  describe ".correct?" do
    it "returns true for a full semver" do
      expect(described_class.correct?("3.10.19")).to be true
    end

    it "returns true for a short minor version" do
      expect(described_class.correct?("3.10")).to be true
    end

    it "returns true for a short major version" do
      expect(described_class.correct?("3")).to be true
    end

    it "returns true for the latest sentinel" do
      expect(described_class.correct?("latest")).to be true
    end

    it "returns true for a pre-release version" do
      expect(described_class.correct?("1.0.0-rc.1")).to be true
    end

    it "returns false for nil" do
      expect(described_class.correct?(nil)).to be false
    end

    it "returns false for garbage" do
      expect(described_class.correct?("not-a-version")).to be false
    end
  end

  describe "#to_s" do
    context "with a numeric version" do
      let(:version_string) { "3.10.19" }

      it "preserves the original string" do
        expect(version.to_s).to eq("3.10.19")
      end
    end

    context "with the latest sentinel" do
      let(:version_string) { "latest" }

      it "preserves the sentinel string" do
        expect(version.to_s).to eq("latest")
      end
    end
  end

  describe "#latest?" do
    it "is true for the sentinel" do
      expect(described_class.new("latest").latest?).to be true
    end

    it "is false for a numeric version" do
      expect(described_class.new("3.10.19").latest?).to be false
    end
  end

  describe "comparison" do
    it "sorts numeric versions correctly" do
      versions = %w(1.0.0 2.0.0 1.1.0 1.0.1).map { |v| described_class.new(v) }
      expect(versions.sort.map(&:to_s)).to eq(%w(1.0.0 1.0.1 1.1.0 2.0.0))
    end

    it "sorts short versions correctly" do
      versions = %w(3.10 3.9 3 3.11).map { |v| described_class.new(v) }
      expect(versions.sort.map(&:to_s)).to eq(%w(3 3.9 3.10 3.11))
    end

    it "sorts the latest sentinel highest" do
      versions = %w(3.10.19 latest 2.0.0).map { |v| described_class.new(v) }
      expect(versions.max.to_s).to eq("latest")
    end

    it "treats two latest sentinels as equal" do
      one = described_class.new("latest")
      another = described_class.new("latest")
      expect(one).to eq(another)
    end
  end
end
