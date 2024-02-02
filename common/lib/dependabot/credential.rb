# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Credential
    extend T::Sig

    sig { params(credential: T::Hash[String, T.any(T::Boolean, String)]).void }
    def initialize(credential)
      raise ArgumentError, "credential must not be nil" if credential.nil?

      @replaces_base = T.let(credential["replaces-base"] == true, T::Boolean)
      credential.delete("replaces-base")
      @credential = T.let(T.unsafe(credential), T::Hash[String, String])
    end

    sig { returns(T::Boolean) }
    def replaces_base?
      @replaces_base
    end

    def [](key)
      @credential[key]
    end

    def fetch(key, *args)
      @credential.fetch(key, *args)
    end

    def keys
      @credential.keys
    end
  end
end
