# frozen_string_literal: true

module Dependabot
  class DependencyGroup
    attr_reader :name, :rules

    def initialize(name:, rules:)
      @name = name
      @rules = rules
    end
  end
end
