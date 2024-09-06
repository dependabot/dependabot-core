# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class VersionSelector
      extend T::Sig
      extend T::Helpers

      # For limited testing, allowing only specific versions defined in engines in package.json
      # such as "20.8.7", "8.1.2", "8.21.2",
      NODE_ENGINE_SUPPORTED_REGEX = /^\d+(?:\.\d+)*$/

      sig { params(manifest_json: T.untyped, name: String).returns(T::Hash[Symbol, T.untyped]) }
      def setup(manifest_json, name)
        engine_versions = manifest_json["engines"]

        if engine_versions.nil?
          Dependabot.logger.info("No info (engines) found")
          return {}
        end

        # logs entries for analysis purposes
        log = engine_versions.select do |engine, _value|
          engine.to_s.match(name)
        end
        Dependabot.logger.info("Found engine info #{log}") unless log.empty?

        # Only keep matching specs versions i.e. "20.21.2", "7.1.2",
        # Additional specs can be added later
        engine_versions.delete_if { |_key, value| !valid_extracted_version?(value) }
        version = engine_versions.select { |engine, _value| engine.to_s.match(name) }

        version
      end

      sig { params(version: String).returns(T::Boolean) }
      def valid_extracted_version?(version)
        version.match?(NODE_ENGINE_SUPPORTED_REGEX)
      end
    end
  end
end
