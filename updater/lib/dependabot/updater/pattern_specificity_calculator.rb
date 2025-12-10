# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "wildcard_matcher"

module Dependabot
  class Updater
    # PatternSpecificityCalculator handles the calculation of pattern specificity scores
    # for dependency group patterns. This enables proper prioritization when a dependency
    # matches multiple groups, ensuring it's only processed by the most specific group.
    #
    # When an `update_type` ("major"|"minor"|"patch") is provided, groups that declare
    # `rules["update-types"]` must include that update_type to be considered as candidates
    # for specificity comparison.
    # When an `applies_to` ("version-updates"|"security-updates") is provided, only groups
    # whose `applies_to` matches will be considered.
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

      EXPLICIT_MEMBER_SCORE = 1000
      EXACT_MATCH_SCORE = 1000
      NO_WILDCARDS_SCORE = 500
      NO_PATTERNS_SCORE = 500
      WILDCARD_BASE_SCORE = 100
      WILDCARD_PENALTY = 10
      UNIVERSAL_WILDCARD_SCORE = 1
      MINIMUM_SCORE = 1
      LENGTH_BONUS_THRESHOLD = 5

      sig do
        params(
          current_group: Dependabot::DependencyGroup,
          dep: Dependabot::Dependency,
          groups: T::Array[Dependabot::DependencyGroup],
          contains_checker:
            T.proc.params(
              group: Dependabot::DependencyGroup,
              dep: Dependabot::Dependency,
              directory: T.nilable(String)
            ).returns(T::Boolean),
          directory: T.nilable(String),
          applies_to: T.nilable(String),
          update_type: T.nilable(String)
        ).returns(T::Boolean)
      end
      def dependency_belongs_to_more_specific_group?(
        current_group,
        dep,
        groups,
        contains_checker,
        directory,
        applies_to: nil,
        update_type: nil
      )
        patterns = cast_patterns(current_group)
        return false unless patterns&.any?

        return false if excluded_by_group?(current_group, dep.name)

        current_group_specificity = calculate_group_specificity_for_dependency(current_group, dep)
        return false if current_group_specificity >= EXPLICIT_MEMBER_SCORE

        groups.any? do |other_group|
          next if other_group == current_group
          next unless update_type_allowed?(other_group, update_type)
          next unless applies_to_allowed?(other_group, applies_to)
          next unless contains_checker.call(other_group, dep, directory)

          other_group_specificity = calculate_group_specificity_for_dependency(other_group, dep)
          other_group_specificity > current_group_specificity
        end
      end

      sig do
        params(
          current_group: Dependabot::DependencyGroup,
          dep: Dependabot::Dependency,
          groups: T::Array[Dependabot::DependencyGroup],
          contains_checker:
            T.proc.params(
              group: Dependabot::DependencyGroup,
              dep: Dependabot::Dependency,
              directory: T.nilable(String)
            ).returns(T::Boolean),
          directory: T.nilable(String),
          applies_to: T.nilable(String),
          update_type: T.nilable(String)
        ).returns(T.nilable(String))
      end
      def find_most_specific_group_name(
        current_group,
        dep,
        groups,
        contains_checker,
        directory,
        applies_to: nil,
        update_type: nil
      )
        return nil unless can_check_specificity?(current_group, dep)

        current_group_specificity = calculate_group_specificity_for_dependency(current_group, dep)
        return nil if current_group_specificity >= EXPLICIT_MEMBER_SCORE

        context = { applies_to: applies_to, update_type: update_type, directory: directory,
                    contains_checker: contains_checker }
        find_highest_specificity_group(current_group, dep, groups, context, current_group_specificity)&.name
      end

      private

      sig { params(group: Dependabot::DependencyGroup, dep: Dependabot::Dependency).returns(T::Boolean) }
      def can_check_specificity?(group, dep)
        patterns = cast_patterns(group)
        return false unless patterns&.any?

        !excluded_by_group?(group, dep.name)
      end

      sig do
        params(
          current_group: Dependabot::DependencyGroup,
          dep: Dependabot::Dependency,
          groups: T::Array[Dependabot::DependencyGroup],
          context: T::Hash[Symbol, T.untyped],
          current_specificity: Integer
        ).returns(T.nilable(Dependabot::DependencyGroup))
      end
      def find_highest_specificity_group(current_group, dep, groups, context, current_specificity)
        most_specific_group = T.let(nil, T.nilable(Dependabot::DependencyGroup))
        highest_specificity = current_specificity

        groups.each do |other_group|
          next if other_group == current_group
          next unless group_matches_context?(other_group, dep, context)

          other_group_specificity = calculate_group_specificity_for_dependency(other_group, dep)
          if other_group_specificity > highest_specificity
            highest_specificity = other_group_specificity
            most_specific_group = other_group
          end
        end

        most_specific_group
      end

      sig do
        params(
          group: Dependabot::DependencyGroup,
          dep: Dependabot::Dependency,
          context: T::Hash[Symbol, T.untyped]
        ).returns(T::Boolean)
      end
      def group_matches_context?(group, dep, context)
        update_type = T.cast(context[:update_type], T.nilable(String))
        applies_to = T.cast(context[:applies_to], T.nilable(String))

        return false unless update_type_allowed?(group, update_type)
        return false unless applies_to_allowed?(group, applies_to)

        contains_checker = T.cast(
          context[:contains_checker],
          T.proc.params(
            group: Dependabot::DependencyGroup,
            dep: Dependabot::Dependency,
            directory: T.nilable(String)
          ).returns(T::Boolean)
        )
        directory = T.cast(context[:directory], T.nilable(String))
        contains_checker.call(group, dep, directory)
      end

      sig { params(group: Dependabot::DependencyGroup, dep: Dependabot::Dependency).returns(Integer) }
      def calculate_group_specificity_for_dependency(group, dep)
        return EXPLICIT_MEMBER_SCORE if group.dependencies.include?(dep)
        return 0 if excluded_by_group?(group, dep.name)

        patterns = cast_patterns(group)
        return NO_PATTERNS_SCORE unless patterns

        matching_patterns = patterns.select { |pattern| WildcardMatcher.match?(pattern, dep.name) }
        return 0 if matching_patterns.empty?

        matching_patterns.map { |pattern| calculate_pattern_specificity(pattern, dep.name) }.max || 0
      end

      sig { params(pattern: String, dep_name: String).returns(Integer) }
      def calculate_pattern_specificity(pattern, dep_name)
        return EXACT_MATCH_SCORE if pattern == dep_name
        return UNIVERSAL_WILDCARD_SCORE if pattern == "*"

        wildcard_count = pattern.count("*")
        return NO_WILDCARDS_SCORE if wildcard_count.zero?

        specificity = WILDCARD_BASE_SCORE - (wildcard_count * WILDCARD_PENALTY)
        length_bonus = [pattern.length - LENGTH_BONUS_THRESHOLD, 0].max

        [specificity + length_bonus, MINIMUM_SCORE].max
      end

      sig { params(group: Dependabot::DependencyGroup, dep_name: String).returns(T::Boolean) }
      def excluded_by_group?(group, dep_name)
        exclude_patterns = T.cast(group.rules["exclude-patterns"], T.nilable(T::Array[String]))
        return false unless exclude_patterns

        exclude_patterns.any? { |pattern| WildcardMatcher.match?(pattern, dep_name) }
      end

      sig { params(group: Dependabot::DependencyGroup, update_type: T.nilable(String)).returns(T::Boolean) }
      def update_type_allowed?(group, update_type)
        return true if update_type.nil?

        group_update_types = T.cast(group.rules["update-types"], T.nilable(T::Array[String]))
        return true unless group_update_types

        group_update_types.include?(update_type)
      end

      sig { params(group: Dependabot::DependencyGroup, applies_to: T.nilable(String)).returns(T::Boolean) }
      def applies_to_allowed?(group, applies_to)
        return true if applies_to.nil?

        group_applies_to = group.applies_to if group.respond_to?(:applies_to)
        return true if group_applies_to.nil?

        group_applies_to == applies_to
      end

      sig { params(group: Dependabot::DependencyGroup).returns(T.nilable(T::Array[String])) }
      def cast_patterns(group)
        T.cast(group.rules["patterns"], T.nilable(T::Array[String]))
      end
    end
  end
end
