# typed: false
# frozen_string_literal: true

require "spec_helper"

# NOTE: This test does not have a corresponding class. It is testing the npm and yarn configuration.
RSpec.describe "bun config" do # rubocop:disable RSpec/DescribeClass
  # NOTE: This comes from updater/config/.npmrc
  it "contains a valid .npmrc config file" do
    npm_result = `npm config list`
    # Output from yarn config set
    expect(npm_result).to include("audit = false")
    expect(npm_result).to include("dry-run = true")
    expect(npm_result).to include("ignore-scripts = true")
  end
end
