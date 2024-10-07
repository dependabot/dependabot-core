# typed: strict
# frozen_string_literal: true

require "dependabot/composer/version"
require "sorbet-runtime"

module Dependabot
  module Composer
    module Helpers
      extend T::Sig

      V1 = T.let("1", String)
      V2 = T.let("2", String)
      # If we are updating a project with no lock file then the default should be the newest version
      DEFAULT = T.let(V2, String)

      # From composers json-schema: https://getcomposer.org/schema.json
      COMPOSER_V2_NAME_REGEX = T.let(
        %r{^[a-z0-9]([_.-]?[a-z0-9]++)*/[a-z0-9](([_.]?|-{0,2})[a-z0-9]++)*$},
        Regexp
      )

      # From https://github.com/composer/composer/blob/b7d770659b4e3ef21423bd67ade935572913a4c1/src/Composer/Repository/PlatformRepository.php#L33
      PLATFORM_PACKAGE_REGEX = T.let(
        /
        ^(?:php(?:-64bit|-ipv6|-zts|-debug)?|hhvm|(?:ext|lib)-[a-z0-9](?:[_.-]?[a-z0-9]+)*
        |composer-(?:plugin|runtime)-api)$
        /x,
        Regexp
      )

      FAILED_GIT_CLONE_WITH_MIRROR = T.let(
        /^Failed to execute git clone --(mirror|checkout)[^']*'(?<url>[^']*?)'/,
        Regexp
      )
      FAILED_GIT_CLONE = T.let(/^Failed to clone (?<url>.*?)/, Regexp)

      sig do
        params(
          composer_json: T::Hash[String, T.untyped],
          parsed_lockfile: T.nilable(T::Hash[String, T.untyped])
        )
          .returns(String)
      end
      def self.composer_version(composer_json, parsed_lockfile = nil)
        v1_unsupported = Dependabot::Experiments.enabled?(:composer_v1_unsupported_error)

        # If the parsed lockfile has a plugin API version, we return either V1 or V2
        # based on the major version of the lockfile.
        if parsed_lockfile && parsed_lockfile["plugin-api-version"]
          version = Composer::Version.new(parsed_lockfile["plugin-api-version"])
          return version.canonical_segments.first == 1 ? V1 : V2
        end

        # Check if the composer name does not follow the Composer V2 naming conventions.
        # This happens if "name" is present in composer.json but doesn't match the required pattern.
        composer_name_invalid = composer_json["name"] && composer_json["name"] !~ COMPOSER_V2_NAME_REGEX

        # If the name is invalid returns the fallback version.
        if composer_name_invalid
          return v1_unsupported ? V2 : V1
        end

        # Check if the composer.json file contains "require" entries that don't follow
        # either the platform package naming conventions or the Composer V2 name conventions.
        invalid_v2 = invalid_v2_requirement?(composer_json)

        # If there are invalid requirements returns fallback version.
        if invalid_v2
          return v1_unsupported ? V2 : V1
        end

        # If no conditions are met return V2 by default.
        V2
      end

      sig { params(message: String).returns(T.nilable(String)) }
      def self.dependency_url_from_git_clone_error(message)
        extract_and_clean_dependency_url(message, FAILED_GIT_CLONE_WITH_MIRROR) ||
          extract_and_clean_dependency_url(message, FAILED_GIT_CLONE)
      end

      sig { params(message: String, regex: Regexp).returns(T.nilable(String)) }
      def self.extract_and_clean_dependency_url(message, regex)
        if (match_data = message.match(regex))
          dependency_url = match_data.named_captures.fetch("url")
          if dependency_url.nil? || dependency_url.empty?
            raise "Could not parse dependency_url from git clone error: #{message}"
          end

          return clean_dependency_url(dependency_url)
        end
        nil
      end

      sig { params(composer_json: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def self.invalid_v2_requirement?(composer_json)
        return false unless composer_json.key?("require")

        composer_json["require"].keys.any? do |key|
          key !~ PLATFORM_PACKAGE_REGEX && key !~ COMPOSER_V2_NAME_REGEX
        end
      end
      private_class_method :invalid_v2_requirement?

      sig { params(dependency_url: String).returns(String) }
      def self.clean_dependency_url(dependency_url)
        return dependency_url unless URI::DEFAULT_PARSER.regexp[:ABS_URI].match?(dependency_url)

        url = URI.parse(dependency_url)
        url.user = nil
        url.password = nil
        url.to_s
      end
      private_class_method :clean_dependency_url
    end
  end
end
