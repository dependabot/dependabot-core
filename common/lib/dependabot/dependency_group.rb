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
      @dependencies.include?(dependency) if @dependencies.any?
      positive_match = rules["patterns"].any? { |rule| WildcardMatcher.match?(rule, dependency.name) }
      negative_match =  rules["exclude-patterns"]&.any? { |rule| WildcardMatcher.match?(rule, dependency.name) } 

      positive_match && !negative_match
    end

    def to_h
      { "name" => name }
    end
  end
end
