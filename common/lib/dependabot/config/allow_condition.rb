# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Config
    # Represents an allow rule entry that restricts updates to specific version ranges.
    # Parallel to IgnoreCondition, but used as a positive filter rather than a denylist.
    #
    # Semantics:
    #   - versions entries are OR-ed: a candidate passes if it satisfies ANY entry.
    #   - commas within one entry string are AND-ed (one band).
    #   - dependency_type scopes the rule to a specific dependency kind.
    #   - security-only updates bypass this filter entirely.
    class AllowCondition
      extend T::Sig

      sig { returns(String) }
      attr_reader :dependency_name

      sig { returns(T::Array[String]) }
      attr_reader :versions

      sig { returns(T.nilable(String)) }
      attr_reader :dependency_type

      sig do
        params(
          dependency_name: String,
          versions: T.nilable(T::Array[String]),
          dependency_type: T.nilable(String)
        ).void
      end
      def initialize(dependency_name:, versions: nil, dependency_type: nil)
        @dependency_name = T.let(dependency_name, String)
        @versions = T.let(versions || [], T::Array[String])
        @dependency_type = T.let(dependency_type, T.nilable(String))
      end

      sig { params(dependency: Dependency, security_updates_only: T::Boolean).returns(T::Array[String]) }
      def allowed_versions(dependency, security_updates_only:) # rubocop:disable Lint/UnusedMethodArgument
        return [] if security_updates_only

        versions
      end
    end
  end
end
