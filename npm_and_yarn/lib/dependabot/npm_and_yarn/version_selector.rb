# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class VersionSelector
      # For limited testing, we are allowing only specific versions defined in engines in package.json
      # such as "v20.8.7", "20.1.2", "V20.21.2",
      NODE_ENGINE_SUPPORTED_REGEX = /^(v|V?)\d*(?:\.\d*\.\d*)?$/

      def setup(manifest_json)
        package_manager = manifest_json["engines"]

        return unless package_manager

        package_manager.each do |key, value|
          package_manager[key] = extracted_version(value)
          Dependabot.logger.info("Engine configuration found : \"#{key}\" : \"#{extracted_version(value)}\"")
        end
      end

      def extracted_version(value)
        if (value.match?(NODE_ENGINE_SUPPORTED_REGEX))
          return value
        else 
          return 0
        end
        
      end
    end
  end
end
