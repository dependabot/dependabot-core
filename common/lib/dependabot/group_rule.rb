# frozen_string_literal: true

module Dependabot
  class GroupRule
    attr_reader :name

    def initialize(name)
      @name = name
    end
  end
end
