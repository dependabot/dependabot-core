# frozen_string_literal: true

require "wildcard_matcher"

module Dependabot
  class DependencyGroup
    attr_reader :name, :rules, :dependencies

    def initialize(name:, rules:)
      @name = name
      @rules = rules
      @dependencies = []
    end

    def contains?(dependency)
      return true if @dependencies.include?(dependency)

      matches_pattern?(dependency.name) && matches_dependency_type?(dependency)
    end

    def to_h
      { "name" => name }
    end

    private

    # TODO: Decouple pattern and exclude-pattern
    #
    # I think we'll probably want to permit someone to group by dependency type but still use exclusions?
    #
    # We probably need to think a lot more about validation to ensure we have _at least one_ positive-match rule
    # out of pattern, dependency-type, etc, as well as `exclude-pattern` or we'll need to support it as an implicit
    # "everything except exclude-patterns" if it can be configured on its own.
    #
    def matches_pattern?(dependency_name)
      return true unless pattern_rules? # If no patterns are defined, we pass this check by default

      positive_match = rules["patterns"].any? { |rule| WildcardMatcher.match?(rule, dependency_name) }
      negative_match = rules["exclude-patterns"]&.any? { |rule| WildcardMatcher.match?(rule, dependency_name) }

      positive_match && !negative_match
    end

    def matches_dependency_type?(dependency)
      return true unless dependency_type_rules? # If no dependency-type is set, match by default

      rules["dependency-type"] == if dependency.production?
                                    "production"
                                  else
                                    "development"
                                  end
    end

    def pattern_rules?
      rules.key?("patterns") && rules["patterns"]&.any?
    end

    def dependency_type_rules?
      rules.key?("dependency-type")
    end
  end
end
