# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Job
    # Parsed representation of a blocked version entry, either from the job
    # definition or fetched from the service mid-job.
    #
    # Replaces the raw T::Hash[String, T.untyped] with a typed struct so
    # downstream code gets compile-time checked field access instead of
    # hash key lookups that return T.untyped.
    class BlockedVersion < T::ImmutableStruct
      extend T::Sig

      const :dependency_name, T.nilable(String)
      const :version_requirement, T.nilable(String)
      const :reason, T.nilable(String)

      # Non-string values are dropped rather than raising so that malformed
      # entries are ignored, matching the previous hash-based filtering.
      # T.untyped is unavoidable here: this parses a freshly-deserialised
      # JSON hash at the wire boundary.
      # rubocop:disable Sorbet/ForbidTUntyped
      sig { params(hash: T::Hash[String, T.untyped]).returns(BlockedVersion) }
      # rubocop:enable Sorbet/ForbidTUntyped
      def self.from_hash(hash)
        name = hash["dependency-name"]
        requirement = hash["version-requirement"]
        reason = hash["reason"]

        new(
          dependency_name: name.is_a?(String) ? name : nil,
          version_requirement: requirement.is_a?(String) ? requirement : nil,
          reason: reason.is_a?(String) ? reason : nil
        )
      end
    end
  end
end
