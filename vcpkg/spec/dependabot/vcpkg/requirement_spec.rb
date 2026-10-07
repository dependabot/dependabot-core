# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/vcpkg/requirement"
require "dependabot/vcpkg/version"

RSpec.describe Dependabot::Vcpkg::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.2.3" }
  let(:version_class) { Dependabot::Vcpkg::Version }

  describe ".new" do
    it "parses an operator that is not separated by whitespace" do
      expect(described_class.new(">=1.2.3").to_s).to eq(">= 1.2.3")
    end

    it "does not let the shorter operator win against the version" do
      expect(described_class.new(">=1.2.3").requirements).to eq([[">=", version_class.new("1.2.3")]])
    end

    it "parses a port version" do
      expect(described_class.new(">=1.2.11#9").to_s).to eq(">= 1.2.11#9")
    end

    it "parses a version with a letter suffix" do
      expect(described_class.new(">=1.1.1n").to_s).to eq(">= 1.1.1n")
    end

    it "parses a version-string scheme value" do
      expect(described_class.new("cares-1_15_0").to_s).to eq("= cares-1_15_0")
    end

    it "defaults to an equality constraint" do
      expect(described_class.new("1.2.3").requirements).to eq([["=", version_class.new("1.2.3")]])
    end

    it "splits a comma separated ignore condition" do
      expect(described_class.new("> 1.2.3, < 2.0").requirements)
        .to contain_exactly([">", version_class.new("1.2.3")], ["<", version_class.new("2.0")])
    end

    it "accepts nil" do
      expect(described_class.new(nil).to_s).to eq(">= 0")
    end
  end

  describe ".requirements_array" do
    it "wraps a single constraint" do
      expect(described_class.requirements_array(">=1.2.3").map(&:to_s)).to eq([">= 1.2.3"])
    end

    it "handles every version shape found in vcpkg advisories" do
      %w(1.1.1n 1.0.2h-1 1.2.11#9 cares-1_15_0 2021-11-01 apache-arrow-0.4.0-1).each do |version_string|
        expect { described_class.requirements_array(version_string) }.not_to raise_error
      end
    end
  end

  describe "#satisfied_by?" do
    it "compares port versions" do
      expect(described_class.new(">=1.2.11#9")).to be_satisfied_by(version_class.new("1.2.11#10"))
      expect(described_class.new(">=1.2.11#9")).not_to be_satisfied_by(version_class.new("1.2.11#8"))
    end

    it "matches an exact string scheme version" do
      expect(described_class.new("=1.1.1n")).to be_satisfied_by(version_class.new("1.1.1n"))
      expect(described_class.new("=1.1.1n")).not_to be_satisfied_by(version_class.new("1.1.1w"))
    end

    it "compares dot versions numerically" do
      expect(described_class.new(">=1.9.0")).to be_satisfied_by(version_class.new("1.10.0"))
    end
  end

  describe "with an unparseable requirement" do
    it "raises" do
      expect { described_class.new(">= >=") }.to raise_error(Gem::Requirement::BadRequirementError)
    end
  end
end
