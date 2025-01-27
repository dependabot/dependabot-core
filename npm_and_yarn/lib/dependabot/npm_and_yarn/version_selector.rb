# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/constraint_helper"

module Dependabot
  module NpmAndYarn
    class VersionSelector
      extend T::Sig
      extend T::Helpers

      sig { params(manifest_json: T::Hash[String, T.untyped], name: String).returns(T::Hash[Symbol, T.untyped]) }
      def setup(manifest_json, name)
        engine_versions = manifest_json["engines"]

        return {} if engine_versions.nil?

        # Find version from engines according to semver speficiations
        # Additional specs can be added later
        version = engine_versions.select do |engine, value|
          engine.to_s.match(name) && ConstraintHelper.find_highest_version_from_constraint_expression(value)
        end

        version
      end
    end
  end
end
