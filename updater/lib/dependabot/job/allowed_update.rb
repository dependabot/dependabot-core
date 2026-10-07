# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Job
    # Parsed representation of an allowed update rule from the job definition.
    #
    # Replaces the raw job hash with a typed struct so
    # downstream code gets compile-time checked field access instead of
    # raw hash key lookups.
    class AllowedUpdate < T::ImmutableStruct
      extend T::Sig

      const :dependency_name, T.nilable(String)
      const :dependency_type, String, default: "all"
      const :update_type, String, default: "all"
      const :update_types, T::Array[String], default: []

      sig { params(hash: T::Hash[String, Object]).returns(AllowedUpdate) }
      def self.from_hash(hash)
        new(
          dependency_name: optional_string(hash["dependency-name"], "dependency-name"),
          dependency_type: string_with_default(hash["dependency-type"], "dependency-type", "all"),
          update_type: string_with_default(hash["update-type"], "update-type", "all"),
          update_types: string_array_with_default(hash["update-types"], "update-types")
        )
      end

      sig { params(value: T.nilable(Object), key: String).returns(T.nilable(String)) }
      def self.optional_string(value, key)
        return if value.nil?
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :optional_string

      sig { params(value: T.nilable(Object), key: String, default: String).returns(String) }
      def self.string_with_default(value, key, default)
        return default if value.nil?
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :string_with_default

      sig { params(value: T.nilable(Object), key: String).returns(T::Array[String]) }
      def self.string_array_with_default(value, key)
        return [] if value.nil?
        raise TypeError, "#{key} must be an array of strings" unless value.is_a?(Array) && value.all?(String)

        value.map { |entry| T.cast(entry, String) }
      end
      private_class_method :string_array_with_default
    end
  end
end
