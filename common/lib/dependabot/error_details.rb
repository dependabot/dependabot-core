# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class ErrorDetails < T::ImmutableStruct
    extend T::Sig

    DetailHash = T.type_alias { T::Hash[T.any(String, Symbol), T.anything] }
    Detail = T.type_alias { T.any(String, DetailHash) }

    const :error_type, String
    const :error_detail, T.nilable(Detail)

    sig { params(hash: T::Hash[Symbol, T.anything]).returns(ErrorDetails) }
    def self.from_hash(hash)
      raw_type = T.cast(hash[:"error-type"], Object)
      raise TypeError, "error-type must be a string" unless raw_type.is_a?(String)

      new(
        error_type: raw_type,
        error_detail: parse_detail(T.cast(hash[:"error-detail"], T.nilable(Object)))
      )
    end

    sig { returns(T::Hash[Symbol, Object]) }
    def to_h
      result = T.let({ "error-type": error_type }, T::Hash[Symbol, Object])
      result[:"error-detail"] = error_detail if error_detail
      result
    end

    sig { params(value: T.nilable(Object)).returns(T.nilable(Detail)) }
    def self.parse_detail(value)
      return if value.nil?
      return value if value.is_a?(String)
      raise TypeError, "error-detail must be a string or hash" unless value.is_a?(Hash)

      result = T.let({}, DetailHash)
      value.each do |raw_key, raw_value|
        key = T.cast(raw_key, Object)
        raise TypeError, "error-detail keys must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)

        result[key] = T.cast(raw_value, Object)
      end
      result
    end
    private_class_method :parse_detail
  end
end
