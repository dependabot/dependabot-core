# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/constraint_helper"

RSpec.describe Dependabot::NpmAndYarn::ConstraintHelper do
  let(:helper) { described_class }
  let(:version_regex) { /^#{helper::VERSION}$/o }

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
  end

  describe ".valid_constraint_expression?" do
    it "returns true for valid constraints" do
      valid_constraints = [
        ">=1.2.3 <2.0.0 || ~3.4.5", "1.2.3", "*", ">=1.0.0-alpha+build"
      ]
      valid_constraints.each do |constraint|
        expect(helper.valid_constraint_expression?(constraint)).to be(true), "Expected #{constraint} to be valid"
      end
    end

    it "returns false for invalid constraints" do
      invalid_constraints = [
        ">=1.2.3 && <2.0.0", ">=x.y.z", "invalid || >=x.y.z"
      ]
      invalid_constraints.each do |constraint|
        expect(helper.valid_constraint_expression?(constraint)).to be(false), "Expected #{constraint} to be invalid"
      end
    end
  end

  describe ".extract_constraints" do
    it "extracts unique constraints from valid expressions" do
      constraints = ">=1.2.3 <2.0.0 || ~2.3.4 || ^3.0.0"
      result = helper.extract_constraints(constraints)
      expect(result).to eq([">=1.2.3", "<2.0.0", ">=2.3.4 <2.4.0", ">=3.0.0 <4.0.0"])
    end

    it "returns nil for invalid constraints" do
      constraints = "invalid || >=x.y.z"
      result = helper.extract_constraints(constraints)
      expect(result).to be_nil
    end
  end

  describe ".find_highest_version_from_constraint_expression" do
    it "finds the highest version from valid constraints" do
      constraints = ">=1.2.3 <2.0.0 || ~2.3.4 || ^3.0.0"
      result = helper.find_highest_version_from_constraint_expression(constraints)
      expect(result).to eq("3.0.0")
    end

    it "returns nil if no versions are present" do
      constraints = "* || invalid"
      result = helper.find_highest_version_from_constraint_expression(constraints)
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
  end
end
