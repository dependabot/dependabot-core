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
        package_manager = manifest_json["engines"]

        return unless package_manager

        # Only keep matching specs versions i.e. "V20.21.2", "20.21.2",
        # Additional specs can be added later
        package_manager.delete_if { |_key, value| !valid_extracted_version(value) }
        package_manager.delete_if { |key, _value| key != name }
        package_manager.each do |key, value|
          Dependabot.logger.info("Found (engines) { \"#{key}\" : \"#{value}\" }")
        end

        package_manager
      end

      def valid_extracted_version(value)
        return true if value.match?(NODE_ENGINE_SUPPORTED_REGEX)

        false
      end
    end
  end
end
