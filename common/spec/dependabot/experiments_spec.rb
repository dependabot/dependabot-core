# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/experiments"

RSpec.describe Dependabot::Experiments do
  before do
    described_class.reset!
  end

  it "can register experiments as enabled" do
    described_class.register(:my_test, true)

    expect(described_class).to be_enabled(:my_test)
  end

  it "works with string names and symbols" do
    described_class.register("my_test", true)

    expect(described_class).to be_enabled("my_test")
    expect(described_class).to be_enabled(:my_test)
  end
end
