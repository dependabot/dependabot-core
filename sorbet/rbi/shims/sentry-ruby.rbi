# typed: strong
# frozen_string_literal: true

module Sentry
  class << self
    sig { params(_blk: T.proc.params(arg0: Sentry::Configuration).void).void }
    def init(&_blk); end

    sig { params(exception: Exception, options: T.untyped).void }
    def capture_exception(exception, **options); end
  end

  class Configuration
    sig { returns(T.nilable(String)) }
    attr_accessor :release

    sig { returns(T.nilable(::Logger)) }
    attr_accessor :logger

    sig { returns(T.nilable(String)) }
    attr_accessor :project_root

    sig { returns(T.nilable(::Regexp)) }
    attr_accessor :app_dirs_pattern

    sig { returns(T::Boolean) }
    attr_accessor :propagate_traces

    sig do
      params(
        value: T.proc
          .params(
            event: ::Sentry::Event,
            hint: T::Hash[Symbol, T.untyped]
          )
          .returns(::Sentry::Event)
      ).void
    end
    def before_send=(value); end

    sig do
      params(
        value: Symbol
      )
        .void
    end
    def instrumenter=(value); end
  end

  class Event; end

  class ErrorEvent < ::Sentry::Event
    sig { returns(::Sentry::ExceptionInterface) }
    attr_reader :exception
  end

  class ExceptionInterface
    sig { returns(T::Array[::Sentry::SingleExceptionInterface]) }
    attr_reader :values
  end

  class SingleExceptionInterface
    sig { returns(String) }
    attr_accessor :value
  end
end
