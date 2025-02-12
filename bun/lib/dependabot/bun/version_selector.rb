# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/bun/constraint_helper"

module Dependabot
  module Bun
    class VersionSelector
      extend T::Sig
      extend T::Helpers

      # For limited testing, allowing only specific versions defined in engines in package.json
      # such as "20.8.7", "8.1.2", "8.21.2",
      NODE_ENGINE_SUPPORTED_REGEX = /^\d+(?:\.\d+)*$/

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

        versions = {}

        if Dependabot::Experiments.enabled?(:enable_engine_version_detection)
          engine_versions.each do |engine, value|
            next unless engine.to_s.match(name)

            versions[name] = ConstraintHelper.find_highest_version_from_constraint_expression(
              value, dependabot_versions
            )
          end
        else
          versions = engine_versions.select do |engine, value|
            engine.to_s.match(name) && valid_extracted_version?(value)
          end
        end

        versions
      end

      sig { params(version: String).returns(T::Boolean) }
      def valid_extracted_version?(version)
        version.match?(NODE_ENGINE_SUPPORTED_REGEX)
      end
    end
  end
end
