# frozen_string_literal: true

module Dependabot
  module Experiments
    @experiments = {}

    def self.reset!
      @experiments = {}
    end

    def self.register(name, value)
      @experiments[name.to_sym] = value
    end

    def self.enabled?(name)
      !!@experiments[name.to_sym]
    end
  end
end
