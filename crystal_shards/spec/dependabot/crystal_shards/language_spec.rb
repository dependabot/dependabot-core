# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/crystal_shards/language"

RSpec.describe Dependabot::CrystalShards::Language do
  describe "#initialize" do
    subject(:language) { described_class.new(version) }

    let(:version) { "1.10.0" }

    it "sets the correct name" do
      expect(language.name).to eq("crystal")
    end

    it "sets the correct version" do
      expect(language.version).to eq(Dependabot::CrystalShards::Version.new("1.10.0"))
    end
  end

  describe "#deprecated?" do
    subject(:language) { described_class.new("1.10.0") }

    it "returns false" do
      expect(language.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    subject(:language) { described_class.new("1.10.0") }

    it "returns false" do
      expect(language.unsupported?).to be false
    end
  end

  describe "LANGUAGE constant" do
    it "is defined as crystal" do
      expect(Dependabot::CrystalShards::LANGUAGE).to eq("crystal")
    end
  end
end
