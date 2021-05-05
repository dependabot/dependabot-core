# frozen_string_literal: true

require "logger"

module Dependabot
  @logger = Logger.new(nil)

  def self.logger
    @logger
  end

  def self.logger=(logger)
    @logger = logger
  end
end
