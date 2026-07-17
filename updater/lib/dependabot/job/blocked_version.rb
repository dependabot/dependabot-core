# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"

module Dependabot
  class Job
    # Parsed representation of a blocked version entry, either from the job
    # definition or fetched from the service mid-job.
    #
    # Replaces the raw job hash with a typed struct so
    # downstream code gets compile-time checked field access instead of
    # hash key lookups that return T.untyped.
    class BlockedVersion < T::ImmutableStruct
      extend T::Sig

      const :dependency_name, T.nilable(String)
      const :version_requirement, T.nilable(String)
      const :reason, T.nilable(String)

      # Non-string values are dropped rather than raising so that malformed
      # entries are ignored, matching the previous hash-based filtering.
      sig { params(hash: T::Hash[String, Object]).returns(BlockedVersion) }
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

      # True when the entry carries both a dependency name and a version
      # requirement we can act on (present and non-blank). Centralises the
      # "is this entry worth considering" predicate shared by Job (ignore
      # requirement extraction) and BlockedVersionDetector (transitive
      # enforcement) so the two cannot drift apart.
      sig { returns(T::Boolean) }
      def usable?
        name = dependency_name
        requirement = version_requirement
        !name.nil? && !name.strip.empty? && !requirement.nil? && !requirement.strip.empty?
      end

      # Filters `entries` to the usable ones whose dependency name matches
      # `dependency_name` once both are normalised for `package_manager`.
      # Matching is exact (no wildcards). Centralises the name-normalisation
      # and equality step shared by Job#matching_blocked_entries and
      # BlockedVersionDetector so neither caller reimplements it.
      sig do
        params(
          entries: T::Array[BlockedVersion],
          dependency_name: String,
          package_manager: String
        ).returns(T::Array[BlockedVersion])
      end
      def self.matching(entries, dependency_name:, package_manager:)
        normaliser = T.must(
          Dependabot::Dependency.name_normaliser_for_package_manager(package_manager)
        )
        target = normaliser.call(dependency_name)

        entries
          .select(&:usable?)
          .select { |entry| normaliser.call(T.must(entry.dependency_name)) == target }
      end
    end
  end
end
