# typed: strict
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

    sig do
      params(
        name: String,
        rules: T::Hash[String, T.untyped],
        applies_to: T.nilable(String)
      )
        .void
    end
    def initialize(name:, rules:, applies_to: "version-updates")
      @name = name
      # For backwards compatibility, if no applies_to is provided, default to "version-updates"
      @applies_to = T.let(applies_to || "version-updates", String)
      @rules = rules
      @dependencies = T.let([], T::Array[Dependabot::Dependency])
    end

    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def contains?(dependency)
      return true if @dependencies.include?(dependency)
      return false if matches_excluded_pattern?(dependency.name)

      matches_pattern?(dependency.name) && matches_dependency_type?(dependency)
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
      return true unless rules.key?("patterns") # If no patterns are defined, we pass this check by default

      T.unsafe(rules["patterns"]).any? { |rule| WildcardMatcher.match?(rule, dependency_name) }
    end

    sig { params(dependency_name: String).returns(T::Boolean) }
    def matches_excluded_pattern?(dependency_name)
      return false unless rules.key?("exclude-patterns") # If there are no exclusions, fail by default

      T.unsafe(rules["exclude-patterns"]).any? { |rule| WildcardMatcher.match?(rule, dependency_name) }
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
  end
end
