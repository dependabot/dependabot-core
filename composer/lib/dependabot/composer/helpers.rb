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
        # If the parsed lockfile has a plugin API version, we return either V1 or V2
        # based on the major version of the lockfile.
        if parsed_lockfile && parsed_lockfile[PackageManager::PLUGIN_API_VERSION_KEY]
          version = Composer::Version.new(parsed_lockfile[PackageManager::PLUGIN_API_VERSION_KEY])
          major_version = version.canonical_segments.first

          return major_version.nil? || major_version > 1 ? V2 : V1
        end

        # Check if the composer name does not follow the Composer V2 naming conventions.
        # This happens if "name" is present in composer.json but doesn't match the required pattern.
        composer_name_invalid = composer_json["name"] && composer_json["name"] !~ COMPOSER_V2_NAME_REGEX

        # If the name is invalid returns the fallback version.
        return V2 if composer_name_invalid

        # Check if the composer.json file contains "require" entries that don't follow
        # either the platform package naming conventions or the Composer V2 name conventions.
        invalid_v2 = invalid_v2_requirement?(composer_json)

        # If there are invalid requirements returns fallback version.
        return V2 if invalid_v2

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

      # Run single composer command returning stdout/stderr
      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def self.package_manager_run_command(command, fingerprint: nil)
        full_command = "composer #{command}"

        Dependabot.logger.info("Running composer command: #{full_command}")

        result = Dependabot::SharedHelpers.run_shell_command(
          full_command,
          fingerprint: "composer #{fingerprint || command}"
        ).strip

        Dependabot.logger.info("Command executed successfully: #{full_command}")
        result
      rescue StandardError => e
        Dependabot.logger.error("Error running composer command: #{full_command}, Error: #{e.message}")
        raise
      end

      # Example output:
      # [dependabot] ~ $ composer --version
      # Composer version 2.7.7 2024-06-10 22:11:12
      # PHP version 7.4.33 (/usr/bin/php7.4)
      # Run the "diagnose" command to get more detailed diagnostics output.
      # Get the version of the composer and php form the command output
      # @return [Hash] with the composer and php version
      # => { composer: "2.7.7", php: "7.4.33" }
      sig { returns(T::Hash[Symbol, T.nilable(String)]) }
      def self.fetch_composer_and_php_versions
        output = package_manager_run_command("--version").strip

        composer_version = capture_version(output, /Composer version (?<version>\d+\.\d+\.\d+)/)
        php_version = capture_version(output, /PHP version (?<version>\d+\.\d+\.\d+)/)

        Dependabot.logger.info("Dependabot running with Composer version: #{composer_version}")
        Dependabot.logger.info("Dependabot running with PHP version: #{php_version}")

        { composer: composer_version, php: php_version }
      rescue StandardError => e
        Dependabot.logger.error("Error fetching versions for package manager and language #{name}: #{e.message}")
        {}
      end

      sig { params(output: String, regex: Regexp).returns(T.nilable(String)) }
      def self.capture_version(output, regex)
        match = output.match(regex)
        match&.named_captures&.fetch("version", nil)
      end

      # Capture the platform PHP version from composer.json
      sig { params(parsed_composer_json: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
      def self.capture_platform_php(parsed_composer_json)
        capture_platform(parsed_composer_json, Language::NAME)
      end

      # Capture the platform extension from composer.json
      sig { params(parsed_composer_json: T::Hash[String, T.untyped], name: String).returns(T.nilable(String)) }
      def self.capture_platform(parsed_composer_json, name)
        parsed_composer_json.dig(PackageManager::CONFIG_KEY, PackageManager::PLATFORM_KEY, name)
      end

      # Capture PHP version constraint from composer.json
      sig { params(parsed_composer_json: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
      def self.php_constraint(parsed_composer_json)
        dependency_constraint(parsed_composer_json, Language::NAME)
      end

      # Capture extension version constraint from composer.json
      sig { params(parsed_composer_json: T::Hash[String, T.untyped], name: String).returns(T.nilable(String)) }
      def self.dependency_constraint(parsed_composer_json, name)
        parsed_composer_json.dig(PackageManager::REQUIRE_KEY, name)
      end

      sig { params(composer_json: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def self.invalid_v2_requirement?(composer_json)
        return false unless composer_json.key?(PackageManager::REQUIRE_KEY)

        composer_json[PackageManager::REQUIRE_KEY].keys.any? do |key|
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
