# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Job
    # Parsed representation of a dependency group from the job definition.
    #
    # Replaces the raw T::Hash[String, T.untyped] with a typed struct so
    # downstream code gets compile-time checked field access instead of
    # hash key lookups that return T.untyped.
    #
    # Named DependencyGroupDefinition to avoid colliding with
    # Dependabot::DependencyGroup, the runtime grouping model this
    # definition is used to build.
    class DependencyGroupDefinition < T::ImmutableStruct
      extend T::Sig

      const :name, T.nilable(String)
      const :applies_to, T.nilable(String)
      # Rules are open-ended, ecosystem-agnostic configuration, so their
      # values cannot be typed more precisely than T.untyped.
      # rubocop:disable Sorbet/ForbidTUntyped
      const :rules, T.nilable(T::Hash[String, T.untyped])
      # rubocop:enable Sorbet/ForbidTUntyped

      # Unexpected value types are coerced to nil rather than raising, so a
      # malformed entry degrades gracefully instead of crashing the job at
      # the parse boundary. T.untyped is unavoidable here: this parses a
      # freshly-deserialised JSON hash at the wire boundary.
      # rubocop:disable Sorbet/ForbidTUntyped
      sig { params(hash: T::Hash[String, T.untyped]).returns(DependencyGroupDefinition) }
      # rubocop:enable Sorbet/ForbidTUntyped
      def self.from_hash(hash)
        name = hash["name"]
        applies_to = hash["applies-to"]
        rules = hash["rules"]

        new(
          name: name.is_a?(String) ? name : nil,
          applies_to: applies_to.is_a?(String) ? applies_to : nil,
          rules: rules.is_a?(Hash) ? rules : nil
        )
      end

      # The wire format of this group definition, used when reporting job
      # errors back to the service.
      # rubocop:disable Sorbet/ForbidTUntyped
      sig { returns(T::Hash[String, T.untyped]) }
      # rubocop:enable Sorbet/ForbidTUntyped
      def to_h
        {
          "name" => name,
          "applies-to" => applies_to,
          "rules" => rules
        }.compact
      end
    end
  end
end
