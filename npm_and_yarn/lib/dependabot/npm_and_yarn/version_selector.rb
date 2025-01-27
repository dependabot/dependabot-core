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
      sig { params(manifest_json: T::Hash[String, T.untyped], name: String).returns(T::Hash[Symbol, T.untyped]) }
      def setup(manifest_json, name)
        engine_versions = manifest_json["engines"]

        # Return an empty hash if no engine versions are specified
        return {} if engine_versions.nil?

        # Select engine versions matching the provided name and satisfying SemVer constraints
        # This adheres to SemVer specifications, ensuring the highest valid version is chosen.
        version = engine_versions.select do |engine, value|
          engine.to_s.match(name) &&
            ConstraintHelper.find_highest_version_from_constraint_expression(value)
        end

        version
      end
    end
  end
end
