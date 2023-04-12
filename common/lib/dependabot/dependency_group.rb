# frozen_string_literal: true

module Dependabot
  class DependencyGroup
    attr_reader :name, :rules, :dependencies

    def initialize(name, rule)
      @name = name
      @rules = rule
      @dependencies = []
    end

    def contains?(dependency)
      @dependencies.include?(dependency) if @dependencies.any?
      rules.any? { |rule| WildcardMatcher.match?(rule, dependency.name) }
    end
  end
end

# Copied from updater/lib/wildcard_matcher.rb
class WildcardMatcher
  def self.match?(wildcard_string, candidate_string)
    return false unless wildcard_string && candidate_string

    regex_string = "a#{wildcard_string.downcase}a".split("*").
                   map { |p| Regexp.quote(p) }.
                   join(".*").gsub(/^a|a$/, "")
    regex = /^#{regex_string}$/
    regex.match?(candidate_string.downcase)
  end
end
