# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module ExceptionCapturer
    extend T::Sig

    # An array of captured exceptions stored for later retrieval
    @captured_exceptions = T.let([], T::Array[StandardError])

    sig { params(error: StandardError).void }
    def self.capture_exception(error:)
      @captured_exceptions << error
    end

    sig { params(block: T.proc.params(error: StandardError).void).void }
    def self.handle_captured_exceptions(&block)
      @captured_exceptions.each(&block)
      clear_captured_exceptions
    end

    sig { returns(T::Array[StandardError]) }
    def self.captured_exceptions
      @captured_exceptions
    end

    sig { void }
    def self.clear_captured_exceptions
      @captured_exceptions = []
    end
  end
end
