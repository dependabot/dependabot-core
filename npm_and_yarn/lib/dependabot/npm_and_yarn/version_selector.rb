# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/constraint_helper"

module Dependabot
  module NpmAndYarn
    class VersionSelector
      extend T::Sig
      extend T::Helpers

      # Sets up engine versions from the given manifest JSON.
      #
      # @param manifest_json [Hash] The manifest JSON containing version information.
      # @param name [String] The engine name to match.
      # @return [Hash] A hash with selected versions, if found.
      sig do
        params(
          manifest_json: T::Hash[String, T.untyped],
          name: String,
          dependabot_versions: T.nilable(T::Array[Dependabot::Version])
        )
          .returns(T::Hash[Symbol, T.untyped])
      end
      def setup(manifest_json, name, dependabot_versions = nil)
        engine_versions = manifest_json["engines"]

        # Return an empty hash if no engine versions are specified
        return {} if engine_versions.nil?

        # Select engine versions matching the provided name and satisfying SemVer constraints
        # This adheres to SemVer specifications, ensuring the highest valid version is chosen.
        version = engine_versions.select do |engine, value|
          engine.to_s.match(name) &&
            ConstraintHelper.find_highest_version_from_constraint_expression(value, dependabot_versions)
        end

        version
      end
    end
  end
end
