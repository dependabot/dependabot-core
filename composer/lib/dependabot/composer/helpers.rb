# frozen_string_literal: true

require "dependabot/composer/version"

module Dependabot
  module Composer
    module Helpers
      # From composers json-schema: https://getcomposer.org/schema.json
      COMPOSER_V2_NAME_REGEX = %r{^[a-z0-9]([_.-]?[a-z0-9]+)*/[a-z0-9](([_.]?|-{0,2})[a-z0-9]+)*$}.freeze
      # From https://github.com/composer/composer/blob/b7d770659b4e3ef21423bd67ade935572913a4c1/src/Composer/Repository/PlatformRepository.php#L33
      PLATFORM_PACKAGE_REGEX = /
        ^(?:php(?:-64bit|-ipv6|-zts|-debug)?|hhvm|(?:ext|lib)-[a-z0-9](?:[_.-]?[a-z0-9]+)*
        |composer-(?:plugin|runtime)-api)$
      /x.freeze

      def self.composer_version(composer_json, parsed_lockfile = nil)
        if parsed_lockfile && parsed_lockfile["plugin-api-version"]
          version = Composer::Version.new(parsed_lockfile["plugin-api-version"])
          return version.canonical_segments.first == 1 ? "v1" : "v2"
        else
          return "v1" if composer_json["name"] && composer_json["name"] !~ COMPOSER_V2_NAME_REGEX
          return "v1" if invalid_v2_requirement?(composer_json)
        end

        "v2"
      end

      def self.invalid_v2_requirement?(composer_json)
        return false unless composer_json.key?("require")

        composer_json["require"].keys.any? do |key|
          key !~ PLATFORM_PACKAGE_REGEX && key !~ COMPOSER_V2_NAME_REGEX
        end
      end
      private_class_method :invalid_v2_requirement?
    end
  end
end
