# typed: strict
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

      sig { params(hash: T::Hash[String, T.untyped]).returns(SecurityAdvisoryEntry) }
      def self.from_hash(hash)
        new(
          dependency_name: hash.fetch("dependency-name"),
          affected_versions: hash.fetch("affected-versions", []) || [],
          patched_versions: hash.fetch("patched-versions", []) || [],
          unaffected_versions: hash.fetch("unaffected-versions", []) || []
        )
      end
    end
  end
end
