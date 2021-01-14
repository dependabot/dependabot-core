# frozen_string_literal: true

require "logger"

module Dependabot
  def self.logger
    @logger ||= Logger.new(nil)
  end

  def self.logger=(logger)
    @logger = logger
  end
end
