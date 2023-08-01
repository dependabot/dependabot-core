# frozen_string_literal: true

require "dependabot/experiments"
require "dependabot/config/ignore_condition"
require "dependabot/logger"

require "wildcard_matcher"
require "yaml"

module Dependabot
  class DependencyGroup
    ANY_DEPENDENCY_NAME = "*"
    SECURITY_UPDATES_ONLY = false

    DEFAULT_UPDATE_TYPES = [
      SEMVER_MAJOR = "major",
      SEMVER_MINOR = "minor",
      SEMVER_PATCH = "patch"
    ].freeze

    IGNORE_CONDITION_TYPES = {
      SEMVER_MAJOR => Dependabot::Config::IgnoreCondition::MAJOR_VERSION_TYPE,
      SEMVER_MINOR => Dependabot::Config::IgnoreCondition::MINOR_VERSION_TYPE,
      SEMVER_PATCH => Dependabot::Config::IgnoreCondition::PATCH_VERSION_TYPE
    }.freeze

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

    # This method generates ignored version ranges for the given Dependency
    # based on the any update-types we have defined.
    def ignored_version_ranges_for(dependency)
      @ignore_condition.ignored_versions(dependency, SECURITY_UPDATES_ONLY)
    end

    def targets_highest_versions_possible?
      return true unless experimental_rules_enabled?

      update_types.include?(SEMVER_MAJOR)
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

    def pattern_rules?
      rules.key?("patterns") && rules["patterns"]&.any?
    end

    def update_types
      rules.fetch("update-types", DEFAULT_UPDATE_TYPES)
    end

    def generate_ignore_condition!
      return NullIgnoreCondition.new unless experimental_rules_enabled?

      ignored_update_types = ignored_update_types_for_rules

      return NullIgnoreCondition.new unless ignored_update_types.any?

      Dependabot.logger.debug("The #{name} group has set ignores for update-type(s): #{ignored_update_types}")

      Dependabot::Config::IgnoreCondition.new(
        dependency_name: ANY_DEPENDENCY_NAME,
        update_types: ignored_update_types
      )
    end

    def ignored_update_types_for_rules
      unless update_types.is_a?(Array)
        raise ArgumentError,
              "The #{name} group has an unexpected value for update-types: '#{update_types}'"
      end

      unless update_types.any?
        raise ArgumentError,
              "The #{name} group has specified an empty array for update-types."
      end

      ignored_update_types = DEFAULT_UPDATE_TYPES - update_types
      return [] if ignored_update_types.empty?

      IGNORE_CONDITION_TYPES.fetch_values(*ignored_update_types)
    end

    def experimental_rules_enabled?
      Dependabot::Experiments.enabled?(:grouped_updates_experimental_rules)
    end
  end
end
