# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Experiments
    extend T::Sig

    @experiments = T.let({}, T::Hash[T.any(String, Symbol), T.anything])

    sig { returns(T::Hash[T.any(String, Symbol), T.anything]) }
    def self.reset!
      @experiments = {}
    end

    sig { params(name: T.any(String, Symbol), value: T.anything).void }
    def self.register(name, value)
      @experiments[name.to_sym] = value
    end

    sig { params(name: T.any(String, Symbol)).returns(T::Boolean) }
    def self.enabled?(name)
      @experiments[name.to_sym] ? true : false
    end
  end
end
