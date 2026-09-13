# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/kotlin_toolchain/requirement"

RSpec.describe Dependabot::KotlinToolchain::Requirement do
  describe ".parse" do
    it "returns a Kotlin Toolchain version" do
      operator, version = described_class.parse("0.12.0-dev-4188")

      expect(operator).to eq("=")
      expect(version).to be_a(Dependabot::KotlinToolchain::Version)
      expect(version.to_s).to eq("0.12.0-dev-4188")
    end
  end

  describe "#satisfied_by?" do
    subject(:requirement) { described_class.new(">= 0.11.0") }

    it "compares against Kotlin Toolchain versions" do
      expect(requirement.satisfied_by?(Gem::Version.new("0.12.0"))).to be(true)
      expect(requirement.satisfied_by?(Gem::Version.new("0.10.0"))).to be(false)
    end
  end

  it "is registered for the ecosystem" do
    expect(Dependabot::Utils.requirement_class_for_package_manager("kotlin_toolchain")).to eq(described_class)
  end
end
