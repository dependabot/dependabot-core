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

      positive_match = rules["patterns"].any? { |rule| WildcardMatcher.match?(rule, dependency.name) }
      negative_match =  rules["exclude-patterns"]&.any? { |rule| WildcardMatcher.match?(rule, dependency.name) }

      positive_match && !negative_match
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

    def generate_ignore_condition!
      return NullIgnoreCondition.new unless rules["update-types"]&.any?

      Dependabot::Config::IgnoreCondition.new(
        dependency_name: ANY_DEPENDENCY_NAME,
        update_types: Dependabot::Config::IgnoreCondition::VERSION_UPDATE_TYPES - rules["update-types"]
      )
    end
  end
end
