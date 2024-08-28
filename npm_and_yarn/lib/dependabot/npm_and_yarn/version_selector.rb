# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class VersionSelector
      def setup(manifest_json)
        package_manager = manifest_json["engines"]

        return unless package_manager

        package_manager.each do |key, value|
          Dependabot.logger.info("Engine configuration found : \"#{key}\" : \"#{value}\"")
        end
      end

      def validate(_name, _version)
        empty
      end

      def requested_version(name); end

      def guessed_version(name); end
    end
  end
end
