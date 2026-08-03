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

    context "with a revision (commit SHA) pin" do
      let(:sha) { "6213ba7a06febe8fef60563a4a7d26a4085783cf" }

      it "is recognised as a revision declaration" do
        expect(described_class.revision_declaration?(".revision(\"#{sha}\")")).to be(true)
        expect(described_class.revision_declaration?('from: "1.0.0"')).to be(false)
      end

      it "extracts the SHA" do
        expect(described_class.extract_revision_sha(".revision(\"#{sha}\")")).to eq(sha)
      end

      it "replaces the SHA" do
        new_sha = "a" * 40
        result = described_class.replace_revision_sha(".revision(\"#{sha}\")", new_sha)
        expect(result).to eq(".revision(\"#{new_sha}\")")
      end

      it "does not raise when instantiated with a revision declaration" do
        expect { described_class.new(".revision(\"#{sha}\")") }.not_to raise_error
      end

      it "reports revision_pinned? as true" do
        req = described_class.new(".revision(\"#{sha}\")")
        expect(req.revision_pinned?).to be(true)
      end

      it "returns the original declaration unchanged from update_if_needed" do
        req = described_class.new(".revision(\"#{sha}\")")
        expect(req.update_if_needed("1.2.3")).to eq(".revision(\"#{sha}\")")
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
end
