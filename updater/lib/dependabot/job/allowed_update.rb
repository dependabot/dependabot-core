# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Job
    # Parsed representation of an allowed update rule from the job definition.
    #
    # Replaces the raw T::Hash[String, T.untyped] with a typed struct so
    # downstream code gets compile-time checked field access instead of
    # hash key lookups that return T.untyped.
    class AllowedUpdate < T::ImmutableStruct
      extend T::Sig

      const :dependency_name, T.nilable(String)
      const :dependency_type, String, default: "all"
      const :update_type, String, default: "all"
      const :update_types, T::Array[String], default: []

      sig { params(hash: T::Hash[String, T.untyped]).returns(AllowedUpdate) }
      def self.from_hash(hash)
        new(
          dependency_name: hash["dependency-name"],
          dependency_type: hash.fetch("dependency-type", "all") || "all",
          update_type: hash.fetch("update-type", "all") || "all",
          update_types: hash.fetch("update-types", []) || []
        )
      end
    end
  end
end
