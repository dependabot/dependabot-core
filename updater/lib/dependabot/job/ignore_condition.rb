# typed: strict
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

      sig { params(hash: T::Hash[String, T.untyped]).returns(IgnoreCondition) }
      def self.from_hash(hash)
        new(
          dependency_name: hash.fetch("dependency-name"),
          version_requirement: hash["version-requirement"],
          update_types: hash["update-types"],
          source: hash["source"]
        )
      end
    end
  end
end
