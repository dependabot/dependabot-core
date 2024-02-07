# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/native_requirement"

RSpec.describe Dependabot::Swift::NativeRequirement do
  RSpec::Matchers.define :parse_as do |requirement|
    match do |declaration|
      described_class.new(declaration).to_s == requirement
    end
  end

  describe ".new" do
    it "parses different ways of declaring requirements" do
      expect('from: "1.0.0"').to parse_as(">= 1.0.0, < 2.0.0")
      expect('from : "1.0.0"').to parse_as(">= 1.0.0, < 2.0.0")

      expect('exact: "1.0.0"').to parse_as("= 1.0.0")
      expect('exact : "1.0.0"').to parse_as("= 1.0.0")

      expect('.upToNextMajor(from: "1.0.0")').to parse_as(">= 1.0.0, < 2.0.0")
      expect('.upToNextMajor (from: "1.0.0")').to parse_as(">= 1.0.0, < 2.0.0")
      expect('.upToNextMajor( from: "1.0.0" )').to parse_as(">= 1.0.0, < 2.0.0")
      expect('.upToNextMajor (from : "1.0.0")').to parse_as(">= 1.0.0, < 2.0.0")

      expect('.upToNextMinor(from: "1.0.0")').to parse_as(">= 1.0.0, < 1.1.0")
      expect('.upToNextMinor (from: "1.0.0")').to parse_as(">= 1.0.0, < 1.1.0")
      expect('.upToNextMinor( from: "1.0.0" )').to parse_as(">= 1.0.0, < 1.1.0")
      expect('.upToNextMinor (from : "1.0.0")').to parse_as(">= 1.0.0, < 1.1.0")

      expect('.exact("1.0.0")').to parse_as("= 1.0.0")
      expect('.exact ("1.0.0")').to parse_as("= 1.0.0")
      expect('.exact( "1.0.0" )').to parse_as("= 1.0.0")

      expect('"1.0.0"..<"2.0.0"').to parse_as(">= 1.0.0, < 2.0.0")
      expect('"1.0.0"..."2.0.0"').to parse_as(">= 1.0.0, <= 2.0.0")
    end
  end
end
