# frozen_string_literal: true

require "dependabot/config/ignore_condition"
require "dependabot/logger"

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

      matches_pattern?(dependency.name)
    end

    # This method generates ignored versions for the given Dependency based on
    # the any update-types we have defined.
    def ignored_versions_for(dependency)
      @ignore_condition.ignored_versions(dependency, SECURITY_UPDATES_ONLY)
    end

    def targets_highest_versions_possible?
      return true unless update_type_rules?

      # If we are grouping by update-type but excluding Major versions then we are leaving
      # some potential updates behind on purpose.
      !rules["update-types"].include?(Dependabot::Config::IgnoreCondition::MAJOR_VERSION_TYPE)
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

    def pattern_rules?
      rules.key?("patterns") && rules["patterns"]&.any?
    end

    # TODO: update-types should probably just be the higest value, not an array
    #
    # Having a group which is major and patch versions is non-sensical, it makes
    # the logic hard to reason about, it should just be a sliding rule where you
    # pick the higest version you want included.
    #
    # We should consider setting it to `minor` by default.
    def generate_ignore_condition!
      return NullIgnoreCondition.new unless update_type_rules?

      invalid_update_types = rules["update-types"] - Dependabot::Config::IgnoreCondition::VERSION_UPDATE_TYPES
      if invalid_update_types.any?
        raise ArgumentError,
              "The #{name} group has unexpected update-type(s): #{invalid_update_types}"
      end

      ignored_update_types = Dependabot::Config::IgnoreCondition::VERSION_UPDATE_TYPES - rules["update-types"]
      # If we are allowing all possible types, then we must use the null object,
      # an IgnoreCondition will interpret an empty array as 'ignore everything'
      return NullIgnoreCondition.new unless ignored_update_types.any?

      Dependabot.logger.debug("The #{name} group has set ignores for update-type(s): #{ignored_update_types}")

      Dependabot::Config::IgnoreCondition.new(
        dependency_name: ANY_DEPENDENCY_NAME,
        update_types: ignored_update_types
      )
    end

    def update_type_rules?
      rules.key?("update-types") && rules["update-types"]&.any?
    end
  end
end
