# typed: strong
# frozen_string_literal: true

module OpenTelemetry
  sig { returns(Trace::TracerProvider) }
  def self.tracer_provider; end

  module SDK
    sig do
      params(
        block: T.nilable(T.proc.params(arg0: Configurator).void)
      )
        .void
    end
    def self.configure(&block); end

    class Configurator
      sig { params(service_name: String, config: T.nilable(T::Hash[String, T.untyped])).void }
      def service_name=(service_name, config = nil); end

      sig { params(instrumentation_name: String).void }
      def use(instrumentation_name); end

      sig { void }
      def use_all; end
    end
  end

  module Trace
    def self.current_span; end

    module Status
      sig { params(message: String).void }
      def self.error(message); end
    end

    module Tracer
      sig do
        type_parameters(:T)
          .params(
            name: String,
            attributes: T.nilable(T::Hash[String, T.untyped]),
            links: T.nilable(T::Array[Link]),
            start_timestamp: T.nilable(Integer),
            kind: T.nilable(Symbol),
            block: T.nilable(T.proc.params(arg0: Span, arg1: Context).returns(T.type_parameter(:T)))
          )
          .returns(T.type_parameter(:T))
      end
      def in_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil, &block); end

      sig do
        params(
          name: String,
          with_parent: T.nilable(Span),
          attributes: T.nilable(T::Hash[String, T.untyped]),
          links: T.nilable(T::Array[Link]),
          start_timestamp: T.nilable(Integer),
          kind: T.nilable(Symbol)
        )
          .returns(Span)
      end
      def start_span(name, with_parent: nil, attributes: nil, links: nil, start_timestamp: nil, kind: nil); end
    end

    class TracerProvider
      sig { params(name: T.nilable(String), version: T.nilable(String)).returns(Tracer) }
      def tracer(name = nil, version = nil); end

      sig { params(timeout: T.nilable(Numeric)).void }
      def shutdown(timeout: nil); end

      sig { params(timeout: T.nilable(Numeric)).void }
      def force_flush(timeout: nil); end
    end

    class Link; end

    class Span
      sig do
        params(
          key: String,
          value: T.untyped
        )
          .returns(T.self_type)
      end
      def set_attribute(key, value); end
      sig { void }
      def finish; end
    end
  end

  class Context
    class Key; end
  end
end
