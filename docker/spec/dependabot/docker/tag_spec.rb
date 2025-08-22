# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/tag"

RSpec.describe Dependabot::Docker::Tag do
  describe "#same_but_more_precise?" do
    it "returns true when receiver is the same version as the parameter, just less precise, false otherwise" do
      expect(described_class.new("2.4").same_but_less_precise?(described_class.new("2.4.2"))).to be true
      expect(described_class.new("2.4").same_but_less_precise?(described_class.new("2.42"))).to be false
    end
  end

  describe "#numeric_version" do
    it "extracts numeric version from standard tags" do
      expect(described_class.new("2.4.2").numeric_version).to eq("2.4.2")
      expect(described_class.new("1.2.3-alpha").numeric_version).to eq("1.2.3")
    end

    it "handles git describe format versions" do
      expect(described_class.new("3.26.3-5-g87159cd").numeric_version).to eq("3.26.3")
      expect(described_class.new("3.26.3.8.g8d771eb").numeric_version).to eq("3.26.3")
      expect(described_class.new("3.26.3-5.g87159cd").numeric_version).to eq("3.26.3")
      expect(described_class.new("1.0.0-10-gabcdef1").numeric_version).to eq("1.0.0")
      expect(described_class.new("2.1.0.5.g1a2b3c4").numeric_version).to eq("2.1.0")
    end

    it "handles edge cases with git hash suffixes" do
      expect(described_class.new("1.2.3-g12345").numeric_version).to eq("1.2.3")
      expect(described_class.new("4.5.6.g789abc").numeric_version).to eq("4.5.6")
    end
  end
end
