# typed: strong
# frozen_string_literal: true

require "logger"
require "sorbet-runtime"

module Dependabot
  extend T::Sig

  sig { returns(::Logger) }
  def self.logger
    @logger ||= T.let(::Logger.new(nil), T.nilable(::Logger))
  end

  sig { params(logger: ::Logger).void }
  def self.logger=(logger)
    @logger = logger
  end
end
