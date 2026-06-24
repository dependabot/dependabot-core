# typed: strong
# frozen_string_literal: true

require "dependabot/experiments"
require "dependabot/config/ignore_condition"
require "dependabot/logger"

require "sorbet-runtime"
require "wildcard_matcher"
require "yaml"

module Dependabot
  class DependencyGroup
    extend T::Sig

    sig { returns(String) }
    attr_reader :name

    sig { returns(T::Hash[String, T.any(String, T::Array[String])]) }
    attr_reader :rules

    sig { returns(T::Array[Dependabot::Dependency]) }
    attr_reader :dependencies

    sig { returns(String) }
    attr_reader :applies_to

    sig { returns(T.nilable(String)) }
    attr_reader :group_by

    # The following readers are parsed once from the raw rules hash so callers
    # get typed access instead of repeatedly casting rules["patterns"] and
    # friends at every use site. A nil value means the rule is absent (which the
    # matching logic treats differently from an empty list).
    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :patterns

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :exclude_patterns

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :update_types

    sig do
      params(
        name: String,
        rules: T::Hash[String, T.any(String, T::Array[String])],
        applies_to: T.nilable(String)
      )
        .void
    end
    def initialize(name:, rules:, applies_to: "version-updates")
      @name = name
      # For backwards compatibility, if no applies_to is provided, default to "version-updates"
      @applies_to = T.let(applies_to || "version-updates", String)
      @rules = rules
      @group_by = T.let(string_rule(rules, "group-by"), T.nilable(String))
      @patterns = T.let(string_array_rule(rules, "patterns"), T.nilable(T::Array[String]))
      @exclude_patterns = T.let(string_array_rule(rules, "exclude-patterns"), T.nilable(T::Array[String]))
      @update_types = T.let(string_array_rule(rules, "update-types"), T.nilable(T::Array[String]))
      @dependencies = T.let([], T::Array[Dependabot::Dependency])
    end

    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def contains?(dependency)
      return true if @dependencies.include?(dependency)
      return false if matches_excluded_pattern?(dependency.name)

      matches_pattern?(dependency.name) && matches_dependency_type?(dependency)
    end

    sig { returns(T::Boolean) }
    def group_by_dependency_name?
      @group_by == "dependency-name"
    end

    sig { returns(T::Hash[String, String]) }
    def to_h
      { "name" => name }
    end

    # Provides a debug utility to view the group as it appears in the config file.
    sig { returns(String) }
    def to_config_yaml
      {
        "groups" => { name => rules }
      }.to_yaml.delete_prefix("---\n")
    end

    private

    sig { params(dependency_name: String).returns(T::Boolean) }
    def matches_pattern?(dependency_name)
      patterns = self.patterns
      return true if patterns.nil? # If no patterns are defined, we pass this check by default

      patterns.any? { |rule| WildcardMatcher.match?(rule, dependency_name) }
    end

    sig { params(dependency_name: String).returns(T::Boolean) }
    def matches_excluded_pattern?(dependency_name)
      exclude_patterns = self.exclude_patterns
      return false if exclude_patterns.nil? # If there are no exclusions, fail by default

      exclude_patterns.any? { |rule| WildcardMatcher.match?(rule, dependency_name) }
    end

    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def matches_dependency_type?(dependency)
      return true unless rules.key?("dependency-type") # If no dependency-type is set, match by default

      rules["dependency-type"] == if dependency.production?
                                    "production"
                                  else
                                    "development"
                                  end
    end

    sig { returns(T::Boolean) }
    def experimental_rules_enabled?
      Dependabot::Experiments.enabled?(:grouped_updates_experimental_rules)
    end

    # Reads a rule whose value is expected to be a single string (e.g.
    # "group-by"), returning nil when the key is absent or the value is not a
    # string.
    sig do
      params(
        rules: T::Hash[String, T.any(String, T::Array[String])],
        key: String
      )
        .returns(T.nilable(String))
    end
    def string_rule(rules, key)
      value = rules[key]
      value.is_a?(String) ? value : nil
    end

    # Reads a rule whose value is expected to be a list of strings (e.g.
    # "patterns", "exclude-patterns", "update-types"). Returns nil when the key
    # is absent so callers can distinguish "rule not set" from "empty list", and
    # coerces a lone string into a single-element list.
    sig do
      params(
        rules: T::Hash[String, T.any(String, T::Array[String])],
        key: String
      )
        .returns(T.nilable(T::Array[String]))
    end
    def string_array_rule(rules, key)
      return nil unless rules.key?(key)

      value = rules[key]
      case value
      when Array then value.grep(String)
      when String then [value]
      else []
      end
    end
  end
end
