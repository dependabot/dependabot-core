# frozen_string_literal: true

require "wildcard_matcher"

module Dependabot
  class DependencyGroup
    attr_reader :name, :rules, :dependencies, :id

    def initialize(name:, rules:)
      @name = name
      @rules = rules
      @dependencies = []
      @id = id_hash
    end

    def contains?(dependency)
      @dependencies.include?(dependency) if @dependencies.any?
      rules.any? { |rule| WildcardMatcher.match?(rule, dependency.name) }
    end

    private

    def id_hash
      { "name" => serialized_group_name }
    end

    def serialized_group_name
      name.downcase.gsub("-", "_").to_sym
    end
  end
end
