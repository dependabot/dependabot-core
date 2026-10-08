# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module UpdateCheckers
    class PeerDependencyConflict < T::ImmutableStruct
      extend T::Sig

      const :requirement_name, String
      const :requirement_version, T.nilable(String)
      const :requiring_dep_name, String

      sig { params(captures: T::Hash[String, T.nilable(String)]).returns(T.nilable(PeerDependencyConflict)) }
      def self.from_captures(captures)
        required = captures["required_dep"]
        requiring = captures["requiring_dep"]
        return unless required && requiring

        new(
          requirement_name: required.sub(/@[^@]+$/, ""),
          requirement_version: required.split("@").last&.delete('"'),
          requiring_dep_name: requiring.sub(/@[^@]+$/, "")
        )
      end

      sig { params(other: PeerDependencyConflict).returns(T::Boolean) }
      def same_dependencies?(other)
        requirement_name == other.requirement_name && requiring_dep_name == other.requiring_dep_name
      end
    end
  end
end
