# frozen_string_literal: true

require "logger"

module Dependabot
  def self.logger
    @logger ||= Logger.new(nil)
  end

  def self.logger=(logger)
    @logger = logger
  end

  def self.with_timer(message)
    start = Time.now.to_i
    Dependabot.logger.debug("Starting #{message}")
    yield
  ensure
    Dependabot.logger.debug("Finished #{message} in #{Time.now.to_i - start} seconds")
  end
end
