# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Job
    # Parsed representation of an ignore condition from the job definition.
    #
    # The raw JSON uses string keys like "dependency-name" and "version-requirement".
    # This struct parses those into typed fields at the boundary so the rest of
    # the codebase gets compile-time field access.
    class IgnoreCondition < T::ImmutableStruct
      extend T::Sig

      const :dependency_name, String
      const :version_requirement, T.nilable(String)
      const :update_types, T.nilable(T::Array[String])
      const :source, T.nilable(String)
      const :updated_at, T.nilable(String)

      sig { params(hash: T::Hash[String, Object]).returns(IgnoreCondition) }
      def self.from_hash(hash)
        new(
          dependency_name: required_string(hash, "dependency-name"),
          version_requirement: optional_string(hash["version-requirement"], "version-requirement"),
          update_types: optional_string_array(hash["update-types"], "update-types"),
          source: optional_string(hash["source"], "source"),
          updated_at: optional_string(hash["updated-at"], "updated-at")
        )
      end

      sig { params(hash: T::Hash[String, Object], key: String).returns(String) }
      def self.required_string(hash, key)
        value = hash.fetch(key)
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :required_string

      sig { params(value: T.nilable(Object), key: String).returns(T.nilable(String)) }
      def self.optional_string(value, key)
        return if value.nil?
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :optional_string

      sig { params(value: T.nilable(Object), key: String).returns(T.nilable(T::Array[String])) }
      def self.optional_string_array(value, key)
        return if value.nil?
        raise TypeError, "#{key} must be an array of strings" unless value.is_a?(Array) && value.all?(String)

        value.map { |entry| T.cast(entry, String) }
      end
      private_class_method :optional_string_array
    end
  end
end
