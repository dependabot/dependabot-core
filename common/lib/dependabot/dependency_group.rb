# frozen_string_literal: true

module Dependabot
  class DependencyGroup
    attr_reader :name

    def initialize(name:)
      @name = name
    end
  end
end
