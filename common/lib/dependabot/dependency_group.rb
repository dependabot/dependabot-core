# frozen_string_literal: true

require "dependabot/config/ignore_condition"

require "wildcard_matcher"
require "yaml"

module Dependabot
  class DependencyGroup
    ANY_DEPENDENCY_NAME = "*"
    SECURITY_UPDATES_ONLY = false

    class NullIgnoreCondition
      def ignored_versions(_dependency, _security_updates_only)
        []
      end
    end

    attr_reader :name, :rules, :dependencies

    def initialize(name:, rules:)
      @name = name
      @rules = rules
      @dependencies = []
      @ignore_condition = generate_ignore_condition!
    end

    def contains?(dependency)
      return true if @dependencies.include?(dependency)
      return false if matches_excluded_pattern?(dependency.name)

      matches_pattern?(dependency.name) && matches_dependency_type?(dependency)
    end

    # This method generates ignored versions for the given Dependency based on
    # the any update-types we have defined.
    def ignored_versions_for(dependency)
      @ignore_condition.ignored_versions(dependency, SECURITY_UPDATES_ONLY)
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

    def generate_ignore_condition!
      return NullIgnoreCondition.new unless rules["update-types"]&.any?

      Dependabot::Config::IgnoreCondition.new(
        dependency_name: ANY_DEPENDENCY_NAME,
        update_types: Dependabot::Config::IgnoreCondition::VERSION_UPDATE_TYPES - rules["update-types"]
      )
    end
  end
end
