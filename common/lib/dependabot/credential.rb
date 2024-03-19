# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "forwardable"

module Dependabot
  class Credential
    extend T::Sig
    extend Forwardable

    def_delegators :@credential, :fetch, :keys, :[]=, :delete, :slice, :values, :entries

    sig { params(credential: T::Hash[String, T.any(T::Boolean, String)]).void }
    def initialize(credential)
      @replaces_base = T.let(credential["replaces-base"] == true, T::Boolean)
      credential.delete("replaces-base")
      @credential = T.let(T.unsafe(credential), T::Hash[String, String])
    end

    sig { returns(T::Boolean) }
    def replaces_base?
      @replaces_base
    end

    sig { params(key: String).returns(T.nilable(String)) }
    def [](key)
      @credential[key]
    end

    sig { params(other: Credential).returns(Credential) }
    def merge(other)
      Credential.new(@credential.merge(other.to_h))
    end

    sig { returns(T::Hash[String, String]) }
    def to_h
      @credential
    end
  end
end
