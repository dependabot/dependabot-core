# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Job
    # Parsed representation of an existing group pull request from the job
    # definition.
    #
    # Replaces the raw job hash with a typed struct so
    # downstream code gets compile-time checked field access instead of
    # raw hash key lookups.
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

        sig { params(hash: T::Hash[String, Object]).returns(Dependency) }
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

      sig { params(hash: T::Hash[String, Object]).returns(ExistingGroupPullRequest) }
      def self.from_hash(hash)
        group_name = hash["dependency-group-name"]
        pr_number = hash["pr_number"]
        dependencies = hash["dependencies"]

        new(
          dependency_group_name: group_name.is_a?(String) ? group_name : nil,
          pr_number: pr_number.is_a?(Integer) ? pr_number : nil,
          dependencies: parsed_dependencies(dependencies)
        )
      end

      sig { params(value: T.nilable(Object)).returns(T.nilable(T::Array[Dependency])) }
      def self.parsed_dependencies(value)
        return unless value.is_a?(Array)

        value.filter_map do |dependency|
          hash = string_hash(T.cast(dependency, Object))
          Dependency.from_hash(hash) if hash
        end
      end
      private_class_method :parsed_dependencies

      sig { params(value: Object).returns(T.nilable(T::Hash[String, Object])) }
      def self.string_hash(value)
        return unless value.is_a?(Hash)

        result = T.let({}, T::Hash[String, Object])
        value.each do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          result[key] = T.cast(raw_value, Object) if key.is_a?(String)
        end
        result
      end
      private_class_method :string_hash
    end
  end
end
