# frozen_string_literal: true

require "logger"

module Dependabot
  module Logger
    def logger
      Dependabot::Logger.logger
    end

    def self.logger
      @logger ||= ::Logger.new(nil)
    end

    def self.logger=(logger)
      @logger = logger
    end
  end
end
