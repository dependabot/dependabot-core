# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module SimpleInstrumentor
    class << self
      extend T::Sig
      extend T::Generic

      sig { returns(T.nilable(T::Array[T.proc.params(name: String, params: T::Hash[Symbol, T.untyped]).void])) }
      attr_accessor :subscribers

      sig { params(block: T.proc.params(name: String, params: T::Hash[Symbol, T.untyped]).void).void }
      def subscribe(&block)
        @subscribers ||= T.let(
          [],
          T.nilable(T::Array[T.proc.params(name: String, params: T::Hash[Symbol, T.untyped]).void])
        )
        @subscribers << block
      end

      sig do
        type_parameters(:T)
          .params(
            name: String,
            params: T::Hash[Symbol, T.untyped],
            block: T.proc.returns(T.type_parameter(:T))
          )
          .returns(T.nilable(T.type_parameter(:T)))
      end
      def instrument(name, params = {}, &block)
        @subscribers&.each { |s| s.call(name, params) }
        yield if block
      end
    end
  end
end
