# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/azure_pipelines/version"

RSpec.describe Dependabot::AzurePipelines::Version do
  describe "#precision" do
    it "counts the dot-separated segments" do
      expect(described_class.new("4").precision).to eq(1)
      expect(described_class.new("4.276").precision).to eq(2)
      expect(described_class.new("0.3.1").precision).to eq(3)
    end
  end

  describe "#truncate" do
    subject(:version) { described_class.new("4.276.1") }

    it "drops segments beyond the requested precision" do
      expect(version.truncate(1).to_s).to eq("4")
      expect(version.truncate(2).to_s).to eq("4.276")
    end

    it "returns itself when the requested precision is not lower" do
      expect(version.truncate(3)).to eq(version)
      expect(version.truncate(5)).to eq(version)
    end

    it "returns a version that compares against other truncated versions" do
      expect(version.truncate(1)).to be < described_class.new("5")
      expect(version.truncate(1)).to eq(described_class.new("4"))
    end
  end

  describe ".correct?" do
    it "accepts the version formats a task reference can use" do
      expect(described_class.correct?("2")).to be(true)
      expect(described_class.correct?("0.3.1")).to be(true)
    end
  end
end
