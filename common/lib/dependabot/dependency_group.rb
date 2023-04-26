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
      rules.any? { |rule| WildcardMatcher.match?(rule, dependency.name) }
    end

    def to_h
      { "name" => name }
    end
  end
end
