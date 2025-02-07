# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Javascript::Bun::Requirement do
  it "inherits initialization from Javascript::Requirement" do
    requirement = described_class.new("1.0.0")
    expect(requirement).to be_a(described_class)
    expect(requirement.to_s).to eq("= 1.0.0")
  end
end
