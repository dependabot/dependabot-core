# typed: strong
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/bun/constraint_helper"

module Dependabot
  module Bun
    class VersionSelector
      extend T::Sig
      extend T::Helpers

      # Sets up the requested engine version from the manifest engines.
      #
      # @param engine_versions [Hash] The manifest engine constraints.
      # @param name [String] The engine name to match.
      # @return [Hash] A hash with selected versions, if found.
      sig do
        params(
          engine_versions: T.nilable(T::Hash[String, String]),
          name: String,
          dependabot_versions: T.nilable(T::Array[Dependabot::Version])
        )
          .returns(T::Hash[String, T.nilable(String)])
      end
      def setup(engine_versions, name, dependabot_versions = nil)
        # Return an empty hash if no engine versions are specified
        return {} if engine_versions.nil?

        versions = T.let({}, T::Hash[String, T.nilable(String)])

        engine_versions.each do |engine, value|
          next unless engine == name

          versions[name] = ConstraintHelper.find_highest_version_from_constraint_expression(
            value, dependabot_versions
          )
        end

        versions
      end
    end
  end
end
