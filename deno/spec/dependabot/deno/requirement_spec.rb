# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/requirement"

RSpec.describe Dependabot::Deno::Requirement do
  subject(:requirement) { described_class.new(constraint) }

  describe ".requirements_array" do
    it "parses a single requirement" do
      reqs = described_class.requirements_array("^1.0.0")
      expect(reqs.length).to eq(1)
    end

    it "handles nil" do
      reqs = described_class.requirements_array(nil)
      expect(reqs.length).to eq(1)
    end
  end

  describe "caret constraints" do
    let(:constraint) { "^1.2.3" }

    it "allows patch and minor bumps" do
      expect(requirement.satisfied_by?(Gem::Version.new("1.2.4"))).to be true
      expect(requirement.satisfied_by?(Gem::Version.new("1.3.0"))).to be true
    end

    it "disallows major bumps" do
      expect(requirement.satisfied_by?(Gem::Version.new("2.0.0"))).to be false
    end

    context "with ^0.x" do
      let(:constraint) { "^0.2.3" }

      it "allows patch bumps only" do
        expect(requirement.satisfied_by?(Gem::Version.new("0.2.4"))).to be true
        expect(requirement.satisfied_by?(Gem::Version.new("0.3.0"))).to be false
      end
    end
  end

  describe "tilde constraints" do
    let(:constraint) { "~1.2.3" }

    it "allows patch bumps" do
      expect(requirement.satisfied_by?(Gem::Version.new("1.2.9"))).to be true
    end

    it "disallows minor bumps" do
      expect(requirement.satisfied_by?(Gem::Version.new("1.3.0"))).to be false
    end
  end

  describe "exact constraints" do
    let(:constraint) { "1.2.3" }

    it "matches exact version" do
      expect(requirement.satisfied_by?(Gem::Version.new("1.2.3"))).to be true
    end

    it "rejects other versions" do
      expect(requirement.satisfied_by?(Gem::Version.new("1.2.4"))).to be false
    end
  end

  describe "range constraints" do
    let(:constraint) { ">=1.0.0" }

    it "matches versions in range" do
      expect(requirement.satisfied_by?(Gem::Version.new("1.0.0"))).to be true
      expect(requirement.satisfied_by?(Gem::Version.new("2.0.0"))).to be true
    end

    it "rejects versions below range" do
      expect(requirement.satisfied_by?(Gem::Version.new("0.9.0"))).to be false
    end
  end
end
