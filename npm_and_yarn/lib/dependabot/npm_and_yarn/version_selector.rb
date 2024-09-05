# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class VersionSelector
      # For limited testing, allowing only specific versions defined in engines in package.json
      # such as "v20.8.7", "20.1.2", "V20.21.2",
      NODE_ENGINE_SUPPORTED_REGEX = /^(v|V?)\d*(?:\.\d*\.\d*)?$/

      def setup(manifest_json, name)
        Dependabot.logger.info("Fetching \"engines\" info")

        engine_versions = manifest_json["engines"]

        if engine_versions.nil?
          Dependabot.logger.info("No info (engines) found")
          return
        end

        # Only keep matching specs versions i.e. "V20.21.2", "20.21.2",
        # Additional specs can be added later
        engine_versions.delete_if { |_key, value| !valid_extracted_version?(value) }
        version = engine_versions.select { |engine, _value| engine.to_s.match(name) }

        engine_versions.each do |key, value|
          Dependabot.logger.info("Found (engines) \"#{key}\" : \"#{value}\"")
        end

        version
      end

      def valid_extracted_version?(version)
        version.match?(NODE_ENGINE_SUPPORTED_REGEX)
      end
    end
  end
end
