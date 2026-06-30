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

    context "with a trailing comma (SE-0439)" do
      it "parses every requirement form" do
        expect(described_class.new('from: "1.0.0",').to_s).to eq(">= 1.0.0, < 2.0.0")
        expect(described_class.new('exact: "1.0.0",').to_s).to eq("= 1.0.0")

        expect(described_class.new('.upToNextMajor(from: "1.0.0",)').to_s).to eq(">= 1.0.0, < 2.0.0")
        expect(described_class.new('.upToNextMajor(from: "1.0.0"),').to_s).to eq(">= 1.0.0, < 2.0.0")
        expect(described_class.new('.upToNextMajor(from: "1.0.0",),').to_s).to eq(">= 1.0.0, < 2.0.0")

        expect(described_class.new('.upToNextMinor(from: "1.0.0",)').to_s).to eq(">= 1.0.0, < 1.1.0")
        expect(described_class.new('.upToNextMinor(from: "1.0.0"),').to_s).to eq(">= 1.0.0, < 1.1.0")
        expect(described_class.new('.upToNextMinor(from: "1.0.0",),').to_s).to eq(">= 1.0.0, < 1.1.0")

        expect(described_class.new('.exact("1.0.0",)').to_s).to eq("= 1.0.0")
        expect(described_class.new('.exact("1.0.0"),').to_s).to eq("= 1.0.0")
        expect(described_class.new('.exact("1.0.0",),').to_s).to eq("= 1.0.0")

        expect(described_class.new('"1.0.0"..<"2.0.0",').to_s).to eq(">= 1.0.0, < 2.0.0")
        expect(described_class.new('"1.0.0"..."2.0.0",').to_s).to eq(">= 1.0.0, <= 2.0.0")
      end
    end

    context "with additional arguments" do
      it "parses every requirement form" do
        expect(described_class.new('from: "1.0.0", traits: [], foo: "bar"').to_s).to eq(">= 1.0.0, < 2.0.0")
        expect(described_class.new('exact: "1.0.0", traits: [], foo: "bar"').to_s).to eq("= 1.0.0")

        expect(described_class.new('.upToNextMajor(from: "1.0.0"), traits: [], foo: "bar"').to_s)
          .to eq(">= 1.0.0, < 2.0.0")
        expect(described_class.new('.upToNextMajor(from: "1.0.0",), traits: [], foo: "bar"').to_s)
          .to eq(">= 1.0.0, < 2.0.0")

        expect(described_class.new('.upToNextMinor(from: "1.0.0"), traits: [], foo: "bar"').to_s)
          .to eq(">= 1.0.0, < 1.1.0")
        expect(described_class.new('.upToNextMinor(from: "1.0.0",), traits: [], foo: "bar"').to_s)
          .to eq(">= 1.0.0, < 1.1.0")

        expect(described_class.new('.exact("1.0.0"), traits: [], foo: "bar"').to_s).to eq("= 1.0.0")
        expect(described_class.new('.exact("1.0.0",), traits: [], foo: "bar"').to_s).to eq("= 1.0.0")

        expect(described_class.new('"1.0.0"..<"2.0.0", traits: [], foo: "bar"').to_s)
          .to eq(">= 1.0.0, < 2.0.0")
        expect(described_class.new('"1.0.0"..."2.0.0", traits: [], foo: "bar"').to_s)
          .to eq(">= 1.0.0, <= 2.0.0")
      end
    end

    context "with prerelease versions" do
      it "correctly computes major bump for prerelease from: declarations" do
        req = described_class.new('from: "1.0.0-beta.1"')
        # Major bump should strip prerelease: 1.0.0 -> 2.0.0
        expect(req.to_s).to include("< 2.0.0")
      end

      it "correctly updates range upper bound with prerelease version" do
        req = described_class.new('"1.0.0"..<"2.0.0"')
        # Updating with a prerelease version should bump major correctly
        result = req.update("1.5.0-rc.1")
        # bump_major("1.5.0-rc.1") strips prerelease, bumps 1.x -> 2.x
        expect(result).to eq('"1.0.0"..<"2.0.0"')
      end

      it "updates exact version to prerelease" do
        req = described_class.new('exact: "1.0.0"')
        result = req.update("2.0.0-beta.1")
        expect(result).to eq('exact: "2.0.0-beta.1"')
      end

      it "updates from: declaration to prerelease" do
        req = described_class.new('from: "1.0.0"')
        result = req.update("2.0.0-beta.1")
        expect(result).to eq('from: "2.0.0-beta.1"')
      end
    end
  end
end
