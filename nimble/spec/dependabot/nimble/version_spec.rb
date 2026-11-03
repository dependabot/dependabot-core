# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nimble/version"

RSpec.describe Dependabot::Nimble::Version do
  it "drops the leading v of a tag" do
    expect(described_class.new("v1.2.3")).to eq(described_class.new("1.2.3"))
    expect(described_class.new("v1.2.3").to_s).to eq("1.2.3")
  end

  it "orders versions" do
    expect(described_class.new("1.10.0")).to be > described_class.new("1.9.0")
    expect(described_class.new("2.0.0-rc1")).to be < described_class.new("2.0.0")
  end

  describe ".correct?" do
    it "accepts versions and v-prefixed tags" do
      expect(described_class.correct?("1.2.3")).to be(true)
      expect(described_class.correct?("v1.2.3")).to be(true)
    end

    it "rejects anything else" do
      expect(described_class.correct?("nightly")).to be(false)
      expect(described_class.correct?(nil)).to be(false)
    end
  end

  it "is the version class of nimble dependencies" do
    expect(Dependabot::Utils.version_class_for_package_manager("nimble")).to eq(described_class)
  end
end
