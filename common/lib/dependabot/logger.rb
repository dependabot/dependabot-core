# typed: strong
# frozen_string_literal: true

require "logger"
require "sorbet-runtime"

module Dependabot
  extend T::Sig

  # Rails.logger in the latest versions is an ActiveSupport::BroadcastLogger
  # which is not a subclass of Logger, but does implement the same interface and
  # can be used interchangeably.
  LoggerType = T.type_alias { T.any(::Logger, ActiveSupport::BroadcastLogger) }

  sig { returns(LoggerType) }
  def self.logger
    @logger ||= T.let(::Logger.new(nil), T.nilable(::Logger))
  end

  sig { params(logger: LoggerType).void }
  def self.logger=(logger)
    @logger = logger
  end
end
