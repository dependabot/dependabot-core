# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Experiments
    extend T::Sig

    @experiments = T.let({}, T::Hash[T.any(String, Symbol), T.untyped])

    sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def self.reset!
      @experiments = {}
    end

    sig { params(name: T.any(String, Symbol), value: T.untyped).void }
    def self.register(name, value)
      @experiments[name.to_sym] = value
    end

    sig { params(name: T.any(String, Symbol)).returns(T::Boolean) }
    def self.enabled?(name)
      !!@experiments[name.to_sym]
    end
  end
end
