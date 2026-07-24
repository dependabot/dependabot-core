# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/powershell/requirement"

RSpec.describe Dependabot::Powershell::Requirement do
  describe ".requirements_array" do
    context "when the requirement string is nil" do
      it "returns a single unconstrained requirement" do
        reqs = described_class.requirements_array(nil)

        expect(reqs.length).to eq(1)
        expect(reqs.first.satisfied_by?(Gem::Version.new("999.0.0"))).to be(true)
      end
    end

    context "when the requirement string is a single constraint" do
      it "parses an exact pin" do
        reqs = described_class.requirements_array("= 1.2.3")

        expect(reqs.length).to eq(1)
        expect(reqs.first.satisfied_by?(Gem::Version.new("1.2.3"))).to be(true)
        expect(reqs.first.satisfied_by?(Gem::Version.new("1.2.4"))).to be(false)
      end

      it "parses a minimum-only constraint" do
        reqs = described_class.requirements_array(">= 1.2.3")

        expect(reqs.first.satisfied_by?(Gem::Version.new("1.2.3"))).to be(true)
        expect(reqs.first.satisfied_by?(Gem::Version.new("5.0.0"))).to be(true)
        expect(reqs.first.satisfied_by?(Gem::Version.new("1.0.0"))).to be(false)
      end
    end

    context "when the requirement string has multiple comma-separated constraints" do
      # A single Gem::Requirement can't parse a comma-joined string directly
      # (it treats the whole string as one "op version" token), so
      # `requirements_array` must split it into separate constraint tokens
      # before constructing the requirement - otherwise this raises
      # Gem::Requirement::BadRequirementError.
      it "builds a single requirement with both constraints ANDed together" do
        reqs = described_class.requirements_array(">= 1.0.0, <= 2.0.0")

        expect(reqs.length).to eq(1)
        expect(reqs.first.satisfied_by?(Gem::Version.new("1.5.0"))).to be(true)
        expect(reqs.first.satisfied_by?(Gem::Version.new("0.9.0"))).to be(false)
        expect(reqs.first.satisfied_by?(Gem::Version.new("2.5.0"))).to be(false)
      end
    end
  end
end
