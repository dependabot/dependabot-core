# typed: true
# frozen_string_literal: true

require "dependabot/experiments"
require "dependabot/config/ignore_condition"
require "dependabot/logger"

require "wildcard_matcher"
require "yaml"

module Dependabot
  class DependencyGroup
    attr_reader :name, :rules, :dependencies, :handled_dependencies

    def initialize(name:, rules:)
      @name = name
      @rules = rules
      @dependencies = []
      @handled_dependencies = Set.new
    end

    def add_to_handled(*dependencies)
      @handled_dependencies += dependencies.map(&:name)
    end

    def add_all_to_handled
      @handled_dependencies += dependencies.map(&:name)
    end

    def contains?(dependency)
      return true if @dependencies.include?(dependency)
      return false if matches_excluded_pattern?(dependency.name)

      matches_pattern?(dependency.name) && matches_dependency_type?(dependency)
    end

    def to_h
      { "name" => name }
    end

    # Provides a debug utility to view the group as it appears in the config file.
    def to_config_yaml
      {
        "groups" => { name => rules }
      }.to_yaml.delete_prefix("---\n")
    end

    private

    def matches_pattern?(dependency_name)
      return true unless rules.key?("patterns") # If no patterns are defined, we pass this check by default

      rules["patterns"].any? { |rule| WildcardMatcher.match?(rule, dependency_name) }
    end

    def matches_excluded_pattern?(dependency_name)
      return false unless rules.key?("exclude-patterns") # If there are no exclusions, fail by default

      rules["exclude-patterns"].any? { |rule| WildcardMatcher.match?(rule, dependency_name) }
    end

    def matches_dependency_type?(dependency)
      return true unless rules.key?("dependency-type") # If no dependency-type is set, match by default

      rules["dependency-type"] == if dependency.production?
                                    "production"
                                  else
                                    "development"
                                  end
    end

    def experimental_rules_enabled?
      Dependabot::Experiments.enabled?(:grouped_updates_experimental_rules)
    end
  end
end
