# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Bun::Requirement do
  it "inherits initialization from Javascript::Requirement" do
    requirement = described_class.new("1.0.0")
    expect(requirement).to be_a(described_class)
    expect(requirement.to_s).to eq("= 1.0.0")
  end

  describe ".requirements_array" do
    it "keeps whitespace-padded comma constraints in one requirement" do
      requirements = described_class.requirements_array(">= 1.0.0 , < 2.0.0")

      expect(requirements.fetch(0).requirements).to eq(
        [
          [">=", Dependabot::Bun::Version.new("1.0.0")],
          ["<", Dependabot::Bun::Version.new("2.0.0")]
        ]
      )
    end

    it "handles repeated whitespace before a hyphen range" do
      requirement_string = "1.0.0#{' ' * 10_000}- 1.5.0"

      expect(described_class.requirements_array(requirement_string))
        .to eq([Gem::Requirement.new(">= 1.0.0", "<= 1.5.0")])
    end
  end
end
