# typed: false
# frozen_string_literal: true

require_relative "../test_helper"
require "dependabot/requirement"
require "dependabot/version"

class RequirementTest < DependabotTestCase
  def setup
    @constraint_string = ">= 1.0, < 2.0"
    @requirement = TestRequirement.new(@constraint_string)
  end

  # Test for #constraints method
  def test_constraints_returns_all_constraint_strings
    requirement = TestRequirement.new(">= 1.0, < 2.0")

    constraints = requirement.constraints

    assert_equal([">= 1.0", "< 2.0"], constraints)
  end

  # Tests for #min_version method
  def test_min_version_with_single_minimum_constraint
    requirement = TestRequirement.new(">= 1.5")

    min_version = requirement.min_version

    assert_equal(Gem::Version.new("1.5"), min_version)
  end

  def test_min_version_with_multiple_minimum_constraints
    requirement = TestRequirement.new(">= 1.0, > 1.5")

    min_version = requirement.min_version

    assert_equal(Gem::Version.new("1.5"), min_version)
  end

  def test_min_version_with_no_minimum_constraints
    requirement = TestRequirement.new("< 2.0")

    min_version = requirement.min_version

    assert_nil(min_version)
  end

  def test_min_version_with_twiddle_wakka_operator_minor_version
    requirement = TestRequirement.new("~> 2.3.0")

    min_version = requirement.min_version

    assert_equal(Gem::Version.new("2.3.0"), min_version)
  end

  # Test using each_test_case for table-driven tests
  def test_min_version_with_various_constraints
    test_cases = [
      [">= 1.5", Gem::Version.new("1.5")],
      [">= 1.0, > 1.5", Gem::Version.new("1.5")],
      ["< 2.0", nil],
      ["~> 2.3.0", Gem::Version.new("2.3.0")]
    ]

    each_test_case(test_cases) do |constraint_string, expected_min_version|
      requirement = TestRequirement.new(constraint_string)
      actual_min_version = requirement.min_version

      if expected_min_version.nil?
        assert_nil(actual_min_version, "Expected nil min_version for constraint: #{constraint_string}")
      else
        assert_equal(expected_min_version, actual_min_version,
                     "Expected min_version #{expected_min_version} for constraint: #{constraint_string}")
      end
    end
  end
end
