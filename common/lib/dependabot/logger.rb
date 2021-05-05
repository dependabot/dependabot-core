# frozen_string_literal: true

require "logger"

module Dependabot
  @@logger = Logger.new(nil) # rubocop:disable Style/ClassVars

  def self.logger
    @@logger
  end

  def self.logger=(logger)
    @@logger = logger # rubocop:disable Style/ClassVars
  end
end
