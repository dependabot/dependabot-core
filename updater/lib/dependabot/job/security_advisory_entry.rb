# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Job
    # Parsed representation of a security advisory from the job definition.
    class SecurityAdvisoryEntry < T::ImmutableStruct
      extend T::Sig

      const :dependency_name, String
      const :affected_versions, T::Array[String], default: []
      const :patched_versions, T::Array[String], default: []
      const :unaffected_versions, T::Array[String], default: []

      sig { params(hash: T::Hash[String, Object]).returns(SecurityAdvisoryEntry) }
      def self.from_hash(hash)
        new(
          dependency_name: required_string(hash, "dependency-name"),
          affected_versions: string_array_with_default(hash["affected-versions"], "affected-versions"),
          patched_versions: string_array_with_default(hash["patched-versions"], "patched-versions"),
          unaffected_versions: string_array_with_default(hash["unaffected-versions"], "unaffected-versions")
        )
      end

      sig { params(hash: T::Hash[String, Object], key: String).returns(String) }
      def self.required_string(hash, key)
        value = hash.fetch(key)
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :required_string

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
