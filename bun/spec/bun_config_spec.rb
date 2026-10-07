# typed: false
# frozen_string_literal: true

require "spec_helper"

# NOTE: This test does not have a corresponding class. It is testing the npm configuration.
RSpec.describe "bun config" do # rubocop:disable RSpec/DescribeClass
  it "silences warning messages that aren't useful within the dependabot context" do
    npm_result = `npm config list`
    expect(npm_result).to include("audit = false")
    expect(npm_result).to include("fund = false")
  end
end
