# frozen_string_literal: true

require "spec_helper"
require "dependabot/experiments"

RSpec.describe Dependabot::Experiments do
  before do
    described_class.reset!
  end

  it "can register experiments as enabled" do
    described_class.register(:my_test, true)

    expect(described_class.enabled?(:my_test)).to be_truthy
  end

  it "works with string names and symbols" do
    described_class.register("my_test", true)

    expect(described_class.enabled?("my_test")).to be_truthy
    expect(described_class.enabled?(:my_test)).to be_truthy
  end
end
