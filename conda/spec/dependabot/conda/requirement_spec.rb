# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/requirement"

RSpec.describe Dependabot::Conda::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  describe ".new" do
    it "creates a requirement from conda-style operators" do
      expect(described_class.new("=1.0.0")).to be_a(described_class)
      expect(described_class.new(">=1.0.0")).to be_a(described_class)
      expect(described_class.new(">1.0.0")).to be_a(described_class)
      expect(described_class.new("<=1.0.0")).to be_a(described_class)
      expect(described_class.new("<1.0.0")).to be_a(described_class)
    end

    it "creates a requirement from pip-style operators" do
      expect(described_class.new("==1.0.0")).to be_a(described_class)
      expect(described_class.new(">=1.0.0")).to be_a(described_class)
      expect(described_class.new("~=1.0.0")).to be_a(described_class)
      expect(described_class.new("!=1.0.0")).to be_a(described_class)
    end

    it "handles complex requirements" do
      expect(described_class.new(">=1.0.0,<2.0.0")).to be_a(described_class)
      expect(described_class.new(">=1.0.0, <2.0.0")).to be_a(described_class)
      expect(described_class.new("=1.0.*")).to be_a(described_class)
    end
  end

  describe "#satisfied_by?" do
    context "with conda-style exact operator" do
      let(:requirement_string) { "=1.2.3" }

      it "is satisfied by exact version" do
        expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.2.3"))
      end

      it "is not satisfied by different version" do
        expect(requirement).not_to be_satisfied_by(Dependabot::Conda::Version.new("1.2.4"))
      end
    end

    context "with pip-style exact operator" do
      let(:requirement_string) { "==1.2.3" }

      it "is satisfied by exact version" do
        expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.2.3"))
      end

      it "is not satisfied by different version" do
        expect(requirement).not_to be_satisfied_by(Dependabot::Conda::Version.new("1.2.4"))
      end
    end

    context "with greater than or equal operator" do
      let(:requirement_string) { ">=1.2.0" }

      it "is satisfied by equal version" do
        expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.2.0"))
      end

      it "is satisfied by greater version" do
        expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.3.0"))
      end

      it "is not satisfied by lesser version" do
        expect(requirement).not_to be_satisfied_by(Dependabot::Conda::Version.new("1.1.0"))
      end
    end

    context "with complex requirement" do
      let(:requirement_string) { ">=1.2.0,<2.0.0" }

      it "is satisfied by version in range" do
        expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.5.0"))
      end

      it "is not satisfied by version below range" do
        expect(requirement).not_to be_satisfied_by(Dependabot::Conda::Version.new("1.1.0"))
      end

      it "is not satisfied by version above range" do
        expect(requirement).not_to be_satisfied_by(Dependabot::Conda::Version.new("2.0.0"))
      end
    end

    context "with wildcard version" do
      let(:requirement_string) { "=1.2.*" }

      it "is satisfied by matching patch version" do
        expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.2.0"))
        expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.2.5"))
      end

      it "is not satisfied by different minor version" do
        expect(requirement).not_to be_satisfied_by(Dependabot::Conda::Version.new("1.3.0"))
      end
    end

    context "with compatible release operator" do
      let(:requirement_string) { "~=1.2.0" }

      it "is satisfied by compatible version" do
        expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.2.5"))
      end

      it "is not satisfied by incompatible version" do
        expect(requirement).not_to be_satisfied_by(Dependabot::Conda::Version.new("1.3.0"))
      end
    end
  end

  describe "#to_s" do
    it "returns the original requirement string" do
      expect(described_class.new(">=1.2.0").to_s).to eq(">=1.2.0")
      expect(described_class.new("=1.2.3").to_s).to eq("=1.2.3")
      expect(described_class.new("==1.2.3").to_s).to eq("==1.2.3")
    end
  end

  describe "#exact?" do
    it "returns true for exact operators" do
      expect(described_class.new("=1.2.3")).to be_exact
      expect(described_class.new("==1.2.3")).to be_exact
    end

    it "returns false for non-exact operators" do
      expect(described_class.new(">=1.2.3")).not_to be_exact
      expect(described_class.new(">1.2.3")).not_to be_exact
      expect(described_class.new("<1.2.3")).not_to be_exact
      expect(described_class.new("~=1.2.3")).not_to be_exact
    end

    it "returns false for multiple requirements" do
      expect(described_class.new(">=1.2.0,<2.0.0")).not_to be_exact
    end
  end

  describe ".parse" do
    it "handles Gem::Version objects" do
      version = Gem::Version.new("1.2.3")
      op, parsed_version = described_class.parse(version)
      expect(op).to eq("=")
      expect(parsed_version).to eq(version)
    end

    it "parses default requirement >=0" do
      op, parsed_version = described_class.parse(">=0")
      expect([op, parsed_version]).to eq(described_class::DefaultRequirement)
    end

    it "raises BadRequirementError for invalid format" do
      expect { described_class.parse("invalid") }.to raise_error(
        Gem::Requirement::BadRequirementError,
        "Illformed requirement [\"invalid\"]"
      )
    end

    it "parses conda-style operators" do
      op, version = described_class.parse("=1.2.3")
      expect(op).to eq("=")
      expect(version.to_s).to eq("1.2.3")
    end

    it "parses pip-style operators" do
      op, version = described_class.parse("==1.2.3")
      expect(op).to eq("==")
      expect(version.to_s).to eq("1.2.3")
    end

    it "handles version without operator" do
      op, version = described_class.parse("1.2.3")
      expect(op).to eq("=")
      expect(version.to_s).to eq("1.2.3")
    end
  end

  describe ".requirements_array" do
    it "returns [new(nil)] when requirement_string is nil" do
      result = described_class.requirements_array(nil)
      expect(result.length).to eq(1)
      expect(result.first.to_s).to eq(">= 0")
    end

    it "splits complex requirements" do
      result = described_class.requirements_array(">=1.0.0,<2.0.0")
      expect(result.length).to eq(2)
      expect(result[0].to_s).to eq(">=1.0.0")
      expect(result[1].to_s).to eq("<2.0.0")
    end

    it "handles single requirements" do
      result = described_class.requirements_array(">=1.0.0")
      expect(result.length).to eq(1)
      expect(result.first.to_s).to eq(">=1.0.0")
    end
  end

  describe "edge cases in initialization" do
    it "handles nil requirement" do
      requirement = described_class.new(nil)
      expect(requirement.to_s).to eq(">= 0")
    end

    it "handles empty string requirement" do
      requirement = described_class.new("")
      expect(requirement.requirements).to eq([[">=", Gem::Version.new("0")]])
    end

    it "handles wildcard requirement" do
      requirement = described_class.new("*")
      expect(requirement.requirements).to eq([[">=", Gem::Version.new("0")]])
    end

    it "handles major version wildcard" do
      requirement = described_class.new("=1.*")
      # Should create range >= 1.0.0, < 2.0.0
      expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.0.0"))
      expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.9.9"))
      expect(requirement).not_to be_satisfied_by(Dependabot::Conda::Version.new("2.0.0"))
    end

    it "handles complex wildcard version (fallback case)" do
      requirement = described_class.new("=1.2.3.*")
      # Should fallback to exact match
      expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.2.3.0"))
    end

    it "converts pip compatible release operator" do
      requirement = described_class.new("~=1.2.0")
      expect(requirement).to be_satisfied_by(Dependabot::Conda::Version.new("1.2.5"))
      expect(requirement).not_to be_satisfied_by(Dependabot::Conda::Version.new("1.3.0"))
    end
  end
end
