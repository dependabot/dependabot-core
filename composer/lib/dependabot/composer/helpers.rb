# frozen_string_literal: true

require "dependabot/composer/version"

module Dependabot
  module Composer
    module Helpers
      # From composers json-schema: https://getcomposer.org/schema.json
      COMPOSER_V2_NAME_REGEX = %r{^[a-z0-9]([_.-]?[a-z0-9]+)*/[a-z0-9](([_.]?|-{0,2})[a-z0-9]+)*$}.freeze

      def self.composer_version(composer_json, parsed_lockfile = nil)
        return "v1" if composer_json["name"] && composer_json["name"] !~ COMPOSER_V2_NAME_REGEX
        return "v2" unless parsed_lockfile && parsed_lockfile["plugin-api-version"]

        version = Composer::Version.new(parsed_lockfile["plugin-api-version"])
        version.canonical_segments.first == 1 ? "v1" : "v2"
      end
    end
  end
end
