# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Job
    # Parsed representation of an existing group pull request from the job
    # definition.
    #
    # Replaces the raw T::Hash[String, T.untyped] with a typed struct so
    # downstream code gets compile-time checked field access instead of
    # hash key lookups that return T.untyped.
    class ExistingGroupPullRequest < T::ImmutableStruct
      extend T::Sig

      # A dependency listed in an existing group pull request.
      #
      # Values are kept exactly as received from the job definition (no
      # directory normalisation) so comparisons against other raw job data
      # behave the same as the previous hash-based access. Values of an
      # unexpected type are dropped rather than raising so that malformed
      # entries are ignored, matching the previous hash-based filtering.
      class Dependency < T::ImmutableStruct
        extend T::Sig

        const :name, T.nilable(String)
        const :version, T.nilable(String)
        const :directory, T.nilable(String)
        const :removed, T::Boolean, default: false

        # T.untyped is unavoidable here: this parses a freshly-deserialised
        # JSON hash at the wire boundary.
        # rubocop:disable Sorbet/ForbidTUntyped
        sig { params(hash: T::Hash[String, T.untyped]).returns(Dependency) }
        # rubocop:enable Sorbet/ForbidTUntyped
        def self.from_hash(hash)
          name = hash["dependency-name"]
          version = hash["dependency-version"]
          directory = hash["directory"]

          new(
            name: name.is_a?(String) ? name : nil,
            version: version.is_a?(String) ? version : nil,
            directory: directory.is_a?(String) ? directory : nil,
            removed: hash["dependency-removed"] == true
          )
        end

        # The wire format of this dependency, with falsey values omitted.
        # Matches the shape produced by DependencyChange#updated_dependencies_set
        # so the two can be compared.
        sig { returns(T::Hash[String, T.any(String, T::Boolean)]) }
        def to_h
          {
            "dependency-name" => name,
            "dependency-version" => version,
            "directory" => directory,
            "dependency-removed" => removed || nil
          }.compact
        end
      end

      const :dependency_group_name, T.nilable(String)
      const :pr_number, T.nilable(Integer)
      const :dependencies, T.nilable(T::Array[Dependency])

      # T.untyped is unavoidable here: this parses a freshly-deserialised
      # JSON hash at the wire boundary.
      # rubocop:disable Sorbet/ForbidTUntyped
      sig { params(hash: T::Hash[String, T.untyped]).returns(ExistingGroupPullRequest) }
      # rubocop:enable Sorbet/ForbidTUntyped
      def self.from_hash(hash)
        group_name = hash["dependency-group-name"]
        pr_number = hash["pr_number"]
        dependencies = hash["dependencies"]

        new(
          dependency_group_name: group_name.is_a?(String) ? group_name : nil,
          pr_number: pr_number.is_a?(Integer) ? pr_number : nil,
          dependencies: dependencies.is_a?(Array) ? dependencies.grep(Hash).map { |d| Dependency.from_hash(d) } : nil
        )
      end
    end
  end
end
