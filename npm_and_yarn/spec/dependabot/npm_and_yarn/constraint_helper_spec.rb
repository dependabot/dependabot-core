# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/constraint_helper"

RSpec.describe Dependabot::NpmAndYarn::ConstraintHelper do
  let(:helper) { described_class }
  let(:version_regex) { /^#{helper::VERSION}$/o }
  let(:dependabot_versions) do
    []
  end

  describe "Regex Constants" do
    describe "VERSION" do
      it "matches valid semantic versions" do
        valid_versions = [
          "1.2.3", "1.2.3-alpha", "1.2.3+build", "1.2.3-alpha+build",
          "0.1.0", "1", "1.0", "1.2.3-0", "1.2.3-0.3.7"
        ]
        valid_versions.each do |version|
          expect(version_regex.match?(version)).to be(true), "Expected #{version} to match"
        end
      end

      it "does not match invalid semantic versions" do
        invalid_versions = [
          "1.2.3-", "1..2.3", "1.2.3_alpha",
          "1.2.-3", "v1.2.3"
        ]
        invalid_versions.each do |version|
          expect(version_regex.match?(version)).to be(false), "Expected #{version} to not match"
        end
      end
    end

    describe "CARET_CONSTRAINT_REGEX" do
      it "matches valid caret constraints" do
        valid_constraints = [
          "^1.2.3", "^0.1.0", "^1.2.3-alpha", "^1.0.0+build", "^1"
        ]
        valid_constraints.each do |constraint|
          expect(helper::CARET_CONSTRAINT_REGEX.match?(constraint)).to be(true), "Expected #{constraint} to match"
        end
      end

      it "does not match invalid caret constraints" do
        invalid_constraints = [
          "^1.2.3-", "^", "1.2.3", "^1.2.3 alpha", "^1.2..3"
        ]
        invalid_constraints.each do |constraint|
          expect(helper::CARET_CONSTRAINT_REGEX.match?(constraint)).to be(false), "Expected #{constraint} to not match"
        end
      end
    end

    describe "TILDE_CONSTRAINT_REGEX" do
      it "matches valid tilde constraints" do
        valid_constraints = [
          "~1.2.3", "~0.1.0", "~1.2.3-alpha", "~1.0.0+build"
        ]
        valid_constraints.each do |constraint|
          expect(helper::TILDE_CONSTRAINT_REGEX.match?(constraint)).to be(true), "Expected #{constraint} to match"
        end
      end

      it "does not match invalid tilde constraints" do
        invalid_constraints = [
          "~1.2.3-", "~", "1.2.3", "~1.2.3 alpha", "~1.2..3"
        ]
        invalid_constraints.each do |constraint|
          expect(helper::TILDE_CONSTRAINT_REGEX.match?(constraint)).to be(false), "Expected #{constraint} to not match"
        end
      end
    end

    describe "EXACT_CONSTRAINT_REGEX" do
      it "matches valid exact constraints" do
        valid_constraints = [
          "1.2.3", "0.1.0", "1.2.3-alpha", "1.0.0+build"
        ]
        valid_constraints.each do |constraint|
          expect(helper::EXACT_CONSTRAINT_REGEX.match?(constraint)).to be(true), "Expected #{constraint} to match"
        end
      end

      it "does not match invalid exact constraints" do
        invalid_constraints = [
          "1.2.3-", "~1.2.3", "^1.2.3", ""
        ]
        invalid_constraints.each do |constraint|
          expect(helper::EXACT_CONSTRAINT_REGEX.match?(constraint)).to be(false), "Expected #{constraint} to not match"
        end
      end
    end

    describe "GREATER_THAN_EQUAL_REGEX" do
      it "matches valid greater-than-or-equal constraints" do
        valid_constraints = [
          ">=1.2.3", ">=1.0.0+build", ">=0.1.0-alpha"
        ]
        valid_constraints.each do |constraint|
          expect(helper::GREATER_THAN_EQUAL_REGEX.match?(constraint)).to be(true), "Expected #{constraint} to match"
        end
      end

      it "does not match invalid greater-than-or-equal constraints" do
        invalid_constraints = [
          ">1.2.3", ">=1.2.3-", ">=1.2.3 alpha", ""
        ]
        invalid_constraints.each do |constraint|
          expect(helper::GREATER_THAN_EQUAL_REGEX.match?(constraint)).to be(false),
                                                                         "Expected #{constraint} to not match"
        end
      end
    end

    describe "LESS_THAN_EQUAL_REGEX" do
      it "matches valid less-than-or-equal constraints" do
        valid_constraints = [
          "<=1.2.3", "<=1.0.0+build", "<=0.1.0-alpha"
        ]
        valid_constraints.each do |constraint|
          expect(helper::LESS_THAN_EQUAL_REGEX.match?(constraint)).to be(true), "Expected #{constraint} to match"
        end
      end

      it "does not match invalid less-than-or-equal constraints" do
        invalid_constraints = [
          "<1.2.3", "<=1.2.3-", "<=1.2.3 alpha", ""
        ]
        invalid_constraints.each do |constraint|
          expect(helper::LESS_THAN_EQUAL_REGEX.match?(constraint)).to be(false), "Expected #{constraint} to not match"
        end
      end
    end

    describe "WILDCARD_REGEX" do
      it "matches valid wildcard constraints" do
        expect(helper::WILDCARD_REGEX.match?("*")).to be(true)
      end

      it "does not match invalid wildcard constraints" do
        invalid_constraints = [
          "**", "1.*", "1.2.*"
        ]
        invalid_constraints.each do |constraint|
          expect(helper::WILDCARD_REGEX.match?(constraint)).to be(false), "Expected #{constraint} to not match"
        end
      end
    end

    describe "LATEST_REGEX" do
      it "matches valid wildcard constraints" do
        expect(helper::LATEST_REGEX.match?("latest")).to be(true)
      end

      it "does not match invalid keyword constraints" do
        expect(helper::LATEST_REGEX.match?("invalid")).to be(false), "Expected invalid to not match"
      end
    end
  end

  describe ".extract_ruby_constraints" do
    it "extracts unique constraints from valid expressions" do
      constraints = ">=1.2.3 <2.0.0 || ~2.3.4 || ^3.0.0"
      result = helper.extract_ruby_constraints(constraints)
      expect(result).to eq([">=1.2.3", "<2.0.0", ">=2.3.4 <2.4.0", ">=3.0.0 <4.0.0"])
    end

    it "returns nil for invalid constraints" do
      constraints = "invalid || >=x.y.z"
      result = helper.extract_ruby_constraints(constraints)
      expect(result).to be_nil
    end

    it "handles constraints with spaces and commas" do
      constraints = ">=1.2.3  ,  <=2.0.0  ,  ~3.4.5"
      result = helper.extract_ruby_constraints(constraints)
      expect(result).to eq([">=1.2.3", "<=2.0.0", ">=3.4.5 <3.5.0"])
    end

    it "handles wildcard versions correctly" do
      expect(helper.extract_ruby_constraints("*")).to eq([])
      expect(helper.extract_ruby_constraints("latest")).to eq([])
    end
  end

  describe ".find_highest_version_from_constraint_expression" do
    let(:dependabot_versions) do
      ["1.2.3", "2.0.0", "3.4.5", "3.5.1", "4.0.0"].map do |v|
        Dependabot::Version.new(v)
      end
    end

    it "finds the highest version from valid constraints" do
      constraints = ">=1.2.3 <2.0.0 || ~2.3.4 || ^3.0.0"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to eq("4.0.0")
    end

    it "handles exact versions correctly" do
      constraints = "3.4.5"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to eq("3.4.5")
    end

    it "handles greater than or equal constraints" do
      constraints = ">=2.0.0"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to eq("4.0.0")
    end

    it "handles less than constraints" do
      constraints = "<3.5.1"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to eq("3.4.5")
    end

    it "handles caret (^) constraints correctly" do
      constraints = "^3.4.5"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to eq("3.4.5") # Matches highest within 3.x.x range
    end

    it "handles tilde (~) constraints correctly" do
      constraints = "~3.4.5"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to eq("3.4.5") # Matches within minor range 3.4.x
    end

    it "handles wildcard (*) constraints correctly" do
      constraints = "*"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to eq("4.0.0") # Highest available version
    end

    it "handles 'latest' constraint correctly" do
      constraints = "latest"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to eq("4.0.0") # Explicit latest resolution
    end

    it "returns nil if no versions match" do
      constraints = ">5.0.0"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to be_nil
    end

    it "returns nil for invalid constraints" do
      constraints = "invalid || >=x.y.z"
      result = helper.find_highest_version_from_constraint_expression(constraints, dependabot_versions)
      expect(result).to be_nil
    end
  end

  describe ".parse_constraints" do
    it "parses valid constraints into hashes" do
      constraints = ">=1.2.3 <2.0.0 || ~2.3.4 || ^3.0.0"
      result = helper.parse_constraints(constraints)
      expect(result).to eq([
        { constraint: ">=1.2.3", version: nil },
        { constraint: "<2.0.0", version: nil },
        { constraint: ">=2.3.4 <2.4.0", version: "2.3.4" },
        { constraint: ">=3.0.0 <4.0.0", version: "3.0.0" }
      ])
    end

    it "returns nil for invalid constraints" do
      constraints = ">=1.2.3 invalid <2.0.0"
      result = helper.parse_constraints(constraints)
      expect(result).to be_nil
    end

    it "handles multiple constraints with spaces and commas" do
      constraints = ">= 1.2.3 , <= 2.0.0 , ~ 3.4.5"
      result = helper.parse_constraints(constraints)
      expect(result).to eq([
        { constraint: ">=1.2.3", version: nil },
        { constraint: "<=2.0.0", version: "2.0.0" },
        { constraint: ">=3.4.5 <3.5.0", version: "3.4.5" }
      ])
    end
  end

  describe ".split_constraints" do
    it "extracts valid semver constraints correctly" do
      valid_constraints = [
        ">=1.2.3", "<=2.0.0", "^3.4.5", "~4.5.6", "1.0.0", "latest", "*"
      ]
      valid_constraints.each do |constraint|
        expect(helper.split_constraints(constraint)).to eq([constraint])
      end
    end

    it "handles spaces between operators and versions" do
      constraints = ">= 1.2.3   <=  2.0.0  ~  3.4.5"
      expect(helper.split_constraints(constraints)).to eq([">=1.2.3", "<=2.0.0", "~3.4.5"])
    end

    it "handles multiple constraints with spaces and commas" do
      constraints = ">= 1.2.3  ,  <= 2.0.0  ,  ~ 3.4.5"
      expect(helper.split_constraints(constraints)).to eq([">=1.2.3", "<=2.0.0", "~3.4.5"])
    end

    it "handles package.json-style OR constraints with spaces" do
      constraints = "^ 1.2.3  ||  >= 2.0.0  < 3.0.0  ||  ~ 3.4.5-beta+build42"
      expect(helper.split_constraints(constraints)).to eq(["^1.2.3", ">=2.0.0", "<3.0.0", "~3.4.5-beta+build42"])
    end

    it "handles wildcard versions correctly" do
      expect(helper.split_constraints("*")).to eq(["*"])
      expect(helper.split_constraints("latest")).to eq(["latest"])
    end

    it "returns an empty array for nil input" do
      expect(helper.split_constraints(nil)).to eq([])
    end

    it "returns an empty array for an empty string" do
      expect(helper.split_constraints("")).to eq([])
    end

    it "returns an empty array for whitespace-only input" do
      expect(helper.split_constraints("    ")).to eq([])
    end

    it "ignores invalid constraints mixed with valid ones" do
      constraints = ">=1.2.3, invalid, <=2.0.0"
      expect(helper.split_constraints(constraints)).to be_nil
    end

    it "extracts prerelease and build versions correctly" do
      constraints = ">= 1.2.3-alpha  <  2.0.0-beta+build.42"
      expect(helper.split_constraints(constraints)).to eq([">=1.2.3-alpha", "<2.0.0-beta+build.42"])
    end

    it "handles complex cases with missing or broken constraints" do
      constraints = ">= 1.2.3 ,, <= 2.0.0 && ^ 3.4.5, * latest"
      expect(helper.split_constraints(constraints)).to be_nil
    end

    it "ignores completely invalid inputs" do
      invalid_constraints = ["random-text", ">>>", "??", "invalid.version"]
      invalid_constraints.each do |constraint|
        expect(helper.split_constraints(constraint)).to be_nil
      end
    end
  end
end
