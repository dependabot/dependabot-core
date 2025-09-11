# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "wildcard_matcher"

module Dependabot
  class Updater
    # PatternSpecificityCalculator handles the calculation of pattern specificity scores
    # for dependency group patterns. This enables proper prioritization when a dependency
    # matches multiple groups, ensuring it's only processed by the most specific group.
    #
    # Specificity scoring hierarchy:
    # - Explicit group members: 1000 (highest)
    # - Exact pattern matches: 1000
    # - Patterns without wildcards: 500
    # - Patterns with wildcards: 100 - (wildcard_count * 10) + length_bonus
    # - Universal wildcard '*': 1 (lowest)
    # - No patterns: 500 (medium)
    class PatternSpecificityCalculator
      extend T::Sig

      # Specificity score constants
      EXPLICIT_MEMBER_SCORE = 1000
      EXACT_MATCH_SCORE = 1000
      NO_WILDCARDS_SCORE = 500
      NO_PATTERNS_SCORE = 500
      WILDCARD_BASE_SCORE = 100
      WILDCARD_PENALTY = 10
      UNIVERSAL_WILDCARD_SCORE = 1
      MINIMUM_SCORE = 1
      LENGTH_BONUS_THRESHOLD = 5

      # Check if a dependency belongs to a more specific group than the current one
      # This prevents generic patterns (like '*') from capturing dependencies
      # that belong to more specific patterns (like 'docker*' or exact names)
      sig do
        params(
          current_group: Dependabot::DependencyGroup,
          dep: Dependabot::Dependency,
          groups: T::Array[Dependabot::DependencyGroup],
          contains_checker:
            T.proc.params(group: Dependabot::DependencyGroup, dep: Dependabot::Dependency, directory: String)
                             .returns(T::Boolean), directory: String
        ).returns(T::Boolean)
      end
      def dependency_belongs_to_more_specific_group?(current_group, dep, groups, contains_checker, directory)
        current_group_specificity = calculate_group_specificity_for_dependency(current_group, dep)

        return false if current_group_specificity >= EXPLICIT_MEMBER_SCORE

        groups.any? do |other_group|
          next if other_group == current_group

          if contains_checker.call(other_group, dep, directory)
            other_group_specificity = calculate_group_specificity_for_dependency(other_group, dep)
            other_group_specificity > current_group_specificity
          else
            false
          end
        end
      end

      private

      # Calculate the specificity score for a dependency within a group
      # Higher scores indicate more specific patterns
      sig { params(group: Dependabot::DependencyGroup, dep: Dependabot::Dependency).returns(Integer) }
      def calculate_group_specificity_for_dependency(group, dep)
        # If dependency is explicitly added to the group, highest specificity
        return EXPLICIT_MEMBER_SCORE if group.dependencies.include?(dep)

        # Check patterns if they exist
        patterns = T.unsafe(group.rules["patterns"])
        return NO_PATTERNS_SCORE unless patterns # No patterns means it matches everything with medium specificity

        matching_patterns = patterns.select { |pattern| WildcardMatcher.match?(pattern, dep.name) }
        return 0 if matching_patterns.empty? # Shouldn't happen if we got here, but safety

        # Find the most specific matching pattern
        matching_patterns.map do |pattern|
          calculate_pattern_specificity(pattern, dep.name)
        end.max || 0
      end

      # Calculate specificity for an individual pattern
      # Higher scores indicate more specific patterns
      sig { params(pattern: String, dep_name: String).returns(Integer) }
      def calculate_pattern_specificity(pattern, dep_name)
        # Exact match gets highest score
        return EXACT_MATCH_SCORE if pattern == dep_name

        # Universal wildcard gets lowest score
        return UNIVERSAL_WILDCARD_SCORE if pattern == "*"

        # Count wildcards and calculate specificity
        wildcard_count = pattern.count("*")
        return NO_WILDCARDS_SCORE if wildcard_count.zero? # No wildcards, exact pattern

        # Patterns with wildcards: base score minus penalty for each wildcard
        specificity = WILDCARD_BASE_SCORE - (wildcard_count * WILDCARD_PENALTY)

        # Additional bonus for longer patterns (more specific context)
        length_bonus = [pattern.length - LENGTH_BONUS_THRESHOLD, 0].max

        [specificity + length_bonus, MINIMUM_SCORE].max # Minimum score of 1
      end
    end
  end
end
