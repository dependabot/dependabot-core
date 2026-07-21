# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
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
  end

  describe ".map_requirements" do
    let(:requirement) do
      Dependabot::Dependency.new(
        name: "swift-nio",
        version: "1.0.0",
        requirements: [{
          requirement: ">= 1.0.0, < 2.0.0",
          file: "Package.swift",
          groups: ["dependencies"],
          source: { type: "git", url: "https://github.com/apple/swift-nio.git" },
          metadata: { requirement_string: 'from: "1.0.0"', custom: "preserved" }
        }],
        package_manager: "swift"
      ).requirements.first
    end

    it "updates the native requirement while preserving its other fields and metadata" do
      updated = described_class.map_requirements([requirement]) { 'from: "2.0.0"' }.first

      expect(updated.requirement).to eq(">= 2.0.0, < 3.0.0")
      expect(updated.file).to eq(requirement.file)
      expect(updated.groups).to eq(requirement.groups)
      expect(updated.source).to eq(requirement.source)
      expect(updated.metadata).to eq(requirement_string: 'from: "2.0.0"', custom: "preserved")
    end
  end
end
