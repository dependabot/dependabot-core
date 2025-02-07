# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Bun::Version do
  it "inherits initialization from Javascript::Version" do
    version = described_class.new("1.0.0")
    expect(version).to be_a(described_class)
    expect(version.to_s).to eq("1.0.0")
  end
end
