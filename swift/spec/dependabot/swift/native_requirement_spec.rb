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
      expect(described_class.new('from: "1.0.0"').to_s).to eq(">= 1.0.0, < 2.0.0")
      expect(described_class.new('from : "1.0.0"').to_s).to eq(">= 1.0.0, < 2.0.0")

      expect(described_class.new('exact: "1.0.0"').to_s).to eq("= 1.0.0")
      expect(described_class.new('exact : "1.0.0"').to_s).to eq("= 1.0.0")

      expect(described_class.new('.upToNextMajor(from: "1.0.0")').to_s).to eq(">= 1.0.0, < 2.0.0")
      expect(described_class.new('.upToNextMajor (from: "1.0.0")').to_s).to eq(">= 1.0.0, < 2.0.0")
      expect(described_class.new('.upToNextMajor( from: "1.0.0" )').to_s).to eq(">= 1.0.0, < 2.0.0")
      expect(described_class.new('.upToNextMajor (from : "1.0.0")').to_s).to eq(">= 1.0.0, < 2.0.0")

      expect(described_class.new('.upToNextMinor(from: "1.0.0")').to_s).to eq(">= 1.0.0, < 1.1.0")
      expect(described_class.new('.upToNextMinor (from: "1.0.0")').to_s).to eq(">= 1.0.0, < 1.1.0")
      expect(described_class.new('.upToNextMinor( from: "1.0.0" )').to_s).to eq(">= 1.0.0, < 1.1.0")
      expect(described_class.new('.upToNextMinor (from : "1.0.0")').to_s).to eq(">= 1.0.0, < 1.1.0")

      expect(described_class.new('.exact("1.0.0")').to_s).to eq("= 1.0.0")
      expect(described_class.new('.exact ("1.0.0")').to_s).to eq("= 1.0.0")
      expect(described_class.new('.exact( "1.0.0" )').to_s).to eq("= 1.0.0")

      expect(described_class.new('"1.0.0"..<"2.0.0"').to_s).to eq(">= 1.0.0, < 2.0.0")
      expect(described_class.new('"1.0.0"..."2.0.0"').to_s).to eq(">= 1.0.0, <= 2.0.0")
    end
  end
end
