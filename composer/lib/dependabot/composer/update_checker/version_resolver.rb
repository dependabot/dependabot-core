# typed: true
# frozen_string_literal: true

require "json"
require "uri"

require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/composer/update_checker"
require "dependabot/composer/version"
require "dependabot/composer/requirement"
require "dependabot/composer/native_helpers"
require "dependabot/composer/file_parser"
require "dependabot/composer/helpers"

module Dependabot
  module Composer
    class UpdateChecker
      class VersionResolver # rubocop:disable Metrics/ClassLength
        class MissingExtensions < StandardError
          attr_reader :extensions

          def initialize(extensions)
            @extensions = extensions
            super
          end
        end

        MISSING_EXPLICIT_PLATFORM_REQ_REGEX =
          %r{
            (?<=PHP\sextension\s)ext\-[^\s\/]+\s.*?\s(?=is|but)|
            (?<=requires\s)php(?:\-[^\s\/]+)?\s.*?\s(?=but)
          }x
        MISSING_IMPLICIT_PLATFORM_REQ_REGEX =
          %r{
            (?<!with|for|by)\sext\-[^\s\/]+\s.*?\s(?=->)|
            (?<=require\s)php(?:\-[^\s\/]+)?\s.*?\s(?=->) # composer v2
          }x
        VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/
        SOURCE_TIMED_OUT_REGEX =
          /The "(?<url>[^"]+packages\.json)".*timed out/

        def initialize(credentials:, dependency:, dependency_files:,
                       requirements_to_unlock:, latest_allowable_version:)
          @credentials                  = credentials
          @dependency                   = dependency
          @dependency_files             = dependency_files
          @requirements_to_unlock       = requirements_to_unlock
          @latest_allowable_version     = latest_allowable_version
          @composer_platform_extensions = initial_platform
          @error_handler                = ComposerErrorHandler.new
        end

        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        private

        attr_reader :credentials
        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :requirements_to_unlock
        attr_reader :latest_allowable_version
        attr_reader :composer_platform_extensions
        attr_reader :error_handler

        def fetch_latest_resolvable_version
          version = fetch_latest_resolvable_version_string
          return if version.nil?
          return unless Composer::Version.correct?(version)

          Composer::Version.new(version)
        rescue MissingExtensions => e
          previous_extensions = composer_platform_extensions.dup
          update_required_extensions(e.extensions)
          raise if previous_extensions == composer_platform_extensions

          retry
        end

        def fetch_latest_resolvable_version_string
          base_directory = dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files
            run_update_checker
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry_count ||= 0
          retry_count += 1
          retry if transitory_failure?(e) && retry_count < 2
          handle_composer_errors(e)
        end

        def write_temporary_dependency_files(unlock_requirement: true)
          write_dependency_file(unlock_requirement: unlock_requirement)
          write_path_dependency_files
          write_zipped_path_dependency_files
          write_lockfile
          write_auth_file
        end

        def write_zipped_path_dependency_files
          zipped_path_dependency_files.each do |file|
            FileUtils.mkdir_p(Pathname.new(file.name).dirname)
            File.write(file.name, file.content)
          end
        end

        def write_dependency_file(unlock_requirement:)
          File.write(
            PackageManager::MANIFEST_FILENAME,
            prepared_composer_json_content(
              unlock_requirement: unlock_requirement
            )
          )
        end

        def write_path_dependency_files
          path_dependency_files.each do |file|
            FileUtils.mkdir_p(Pathname.new(file.name).dirname)
            File.write(file.name, file.content)
          end
        end

        def write_lockfile
          File.write(PackageManager::LOCKFILE_FILENAME, lockfile.content) if lockfile
        end

        def write_auth_file
          File.write(PackageManager::AUTH_FILENAME, auth_json.content) if auth_json
        end

        def transitory_failure?(error)
          return true if error.message.include?("404 Not Found")
          return true if error.message.include?("timed out")
          return true if error.message.include?("Temporary failure")

          error.message.include?("Content-Length mismatch")
        end

        def run_update_checker
          SharedHelpers.with_git_configured(credentials: credentials) do
            SharedHelpers.run_helper_subprocess(
              command: "php -d memory_limit=-1 #{php_helper_path}",
              allow_unsafe_shell_command: true,
              function: "get_latest_resolvable_version",
              args: [
                Dir.pwd,
                dependency.name.downcase,
                git_credentials,
                registry_credentials
              ]
            )
          end
        end

        def prepared_composer_json_content(unlock_requirement: true)
          content = composer_file.content
          content = unlock_dep_being_updated(content) if unlock_requirement
          content = lock_git_dependencies(content) if lockfile
          content = add_temporary_platform_extensions(content)
          content
        end

        def unlock_dep_being_updated(content)
          content.gsub(
            /"#{Regexp.escape(dependency.name)}"\s*:\s*".*"/,
            %("#{dependency.name}": "#{updated_version_requirement_string}")
          )
        end

        def add_temporary_platform_extensions(content)
          json = JSON.parse(content)

          composer_platform_extensions.each do |extension, requirements|
            next unless version_for_reqs(requirements)

            json[PackageManager::CONFIG_KEY] ||= {}
            json[PackageManager::CONFIG_KEY][PackageManager::PLATFORM_KEY] ||= {}
            json[PackageManager::CONFIG_KEY][PackageManager::PLATFORM_KEY][extension] =
              version_for_reqs(requirements)
          end

          JSON.dump(json)
        end

        def lock_git_dependencies(content)
          json = JSON.parse(content)

          FileParser::DEPENDENCY_GROUP_KEYS.each do |keys|
            next unless json[keys[:manifest]]

            json[keys[:manifest]].each do |name, req|
              next unless req.start_with?("dev-")
              next if req.include?("#")

              commit_sha = parsed_lockfile
                           .fetch(keys[:lockfile], [])
                           .find { |d| d["name"] == name }
                           &.dig("source", "reference")
              updated_req_parts = req.split
              updated_req_parts[0] = updated_req_parts[0] + "##{commit_sha}"
              json[keys[:manifest]][name] = updated_req_parts.join(" ")
            end
          end

          JSON.dump(json)
        end

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        def updated_version_requirement_string
          lower_bound =
            if requirements_to_unlock == :none
              dependency.requirements.first&.fetch(:requirement) || ">= 0"
            elsif dependency.version
              ">= #{dependency.version}"
            else
              version_for_requirement =
                dependency.requirements.filter_map { |r| r[:requirement] }
                          .reject { |req_string| req_string.start_with?("<") }
                          .select { |req_string| req_string.match?(VERSION_REGEX) }
                          .map { |req_string| req_string.match(VERSION_REGEX) }
                          .select { |version| requirement_valid?(">= #{version}") }
                          .max_by { |version| Composer::Version.new(version.to_s) }

              ">= #{version_for_requirement || 0}"
            end

          # Add the latest_allowable_version as an upper bound. This means
          # ignore conditions are considered when checking for the latest
          # resolvable version.
          #
          # NOTE: This isn't perfect. If v2.x is ignored and v3 is out but
          # unresolvable then the `latest_allowable_version` will be v3, and
          # we won't be ignoring v2.x releases like we should be.
          return lower_bound unless latest_allowable_version

          # If the original requirement is just a stability flag we append that
          # flag to the requirement
          return "==#{latest_allowable_version}#{lower_bound.strip}" if lower_bound.strip.start_with?("@")

          lower_bound + ", == #{latest_allowable_version}"
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/AbcSize

        # TODO: Extract error handling and share between the lockfile updater
        #
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/MethodLength
        def handle_composer_errors(error)
          # Special case for Laravel Nova, which will fall back to attempting
          # to close a private repo if given invalid (or no) credentials
          if error.message.include?("github.com/laravel/nova.git")
            raise PrivateSourceAuthenticationFailure, "nova.laravel.com"
          end

          dependency_url = Helpers.dependency_url_from_git_clone_error(error.message)
          if dependency_url
            raise Dependabot::GitDependenciesNotReachable, dependency_url
          elsif unresolvable_error?(error)
            raise Dependabot::DependencyFileNotResolvable, error.message
          elsif error.message.match?(MISSING_EXPLICIT_PLATFORM_REQ_REGEX)
            # These errors occur when platform requirements declared explicitly
            # in the composer.json aren't met.
            missing_extensions =
              error.message.scan(MISSING_EXPLICIT_PLATFORM_REQ_REGEX)
                   .map do |extension_string|
                name, requirement = extension_string.strip.split(" ", 2)
                { name: name, requirement: requirement }
              end
            raise MissingExtensions, missing_extensions
          elsif error.message.match?(MISSING_IMPLICIT_PLATFORM_REQ_REGEX) &&
                !library? &&
                !initial_platform.empty? &&
                implicit_platform_reqs_satisfiable?(error.message)
            missing_extensions =
              error.message.scan(MISSING_IMPLICIT_PLATFORM_REQ_REGEX)
                   .map do |extension_string|
                name, requirement = extension_string.strip.split(" ", 2)
                { name: name, requirement: requirement }
              end

            missing_extension = missing_extensions.find do |hash|
              existing_reqs = composer_platform_extensions[hash[:name]] || []
              version_for_reqs(existing_reqs + [hash[:requirement]])
            end

            raise MissingExtensions, [missing_extension]
          elsif error.message.include?("cannot require itself") ||
                error.message.include?('packages.json" file could not be down')
            raise Dependabot::DependencyFileNotResolvable, error.message
          elsif error.message.include?("No driver found to handle VCS") &&
                !error.message.include?("@") && !error.message.include?("://")
            msg = "Dependabot detected a VCS requirement with a local path, " \
                  "rather than a URL. Dependabot does not support this " \
                  "setup.\n\nThe underlying error was:\n\n#{error.message}"
            raise Dependabot::DependencyFileNotResolvable, msg
          elsif error.message.include?("requirements could not be resolved")
            # If there's no lockfile, there's no difference between running
            # `composer install` and `composer update`, so we can easily check
            # whether the existing requirements are resolvable for an install
            check_original_requirements_resolvable unless lockfile

            # If there *is* a lockfile we can't confidently distinguish between
            # cases where we can't install and cases where we can't update. For
            # now, we therefore just ignore the dependency and log the error.

            Dependabot.logger.error(error.message)
            error.backtrace.each { |line| Dependabot.logger.error(line) }
            nil
          elsif error.message.include?("URL required authentication") ||
                error.message.include?("403 Forbidden")
            source = error.message.match(%r{https?://(?<source>[^/]+)/}).named_captures.fetch("source")
            raise Dependabot::PrivateSourceAuthenticationFailure, source
          elsif error.message.match?(SOURCE_TIMED_OUT_REGEX)
            url = error.message.match(SOURCE_TIMED_OUT_REGEX).named_captures.fetch("url")
            raise if [
              "packagist.org",
              "www.packagist.org"
            ].include?(URI(url).host)

            source = url.gsub(%r{/packages.json$}, "")
            raise Dependabot::PrivateSourceTimedOut, source
          elsif error.message.start_with?("Allowed memory size", "Out of memory")
            raise Dependabot::OutOfMemory
          elsif error.error_context[:process_termsig] == Dependabot::SharedHelpers::SIGKILL
            # If the helper was SIGKILL-ed, assume the OOMKiller did it
            raise Dependabot::OutOfMemory
          elsif error.message.start_with?("Package not found in updated") &&
                !dependency.top_level?
            # If we can't find the dependency in the composer.lock after an
            # update, but it was originally a sub-dependency, it's because the
            # dependency is no longer required and is just cruft in the
            # composer.json. In this case we just ignore the dependency.
            nil
          elsif error.message.include?("does not match the expected JSON schema")
            msg = "Composer failed to parse your #{PackageManager::MANIFEST_FILENAME}" \
                  "as it does not match the expected JSON schema.\n" \
                  "Run `composer validate` to check your #{PackageManager::MANIFEST_FILENAME} " \
                  "and #{PackageManager::LOCKFILE_FILENAME} files.\n\n" \
                  "See https://getcomposer.org/doc/04-schema.md for details on the schema."
            raise Dependabot::DependencyFileNotParseable, msg
          else
            error_handler.handle_composer_error(error)

            raise error
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/MethodLength

        def unresolvable_error?(error)
          error.message.start_with?("Could not parse version") ||
            error.message.include?("does not allow connections to http://") ||
            error.message.match?(/The `url` supplied for the path .* does not exist/) ||
            error.message.start_with?("Invalid version string")
        end

        def library?
          parsed_composer_file["type"] == "library"
        end

        def implicit_platform_reqs_satisfiable?(message)
          missing_extensions =
            message.scan(MISSING_IMPLICIT_PLATFORM_REQ_REGEX)
                   .map do |extension_string|
              name, requirement = extension_string.strip.split(" ", 2)
              { name: name, requirement: requirement }
            end

          missing_extensions.any? do |hash|
            existing_reqs = composer_platform_extensions[hash[:name]] || []
            version_for_reqs(existing_reqs + [hash[:requirement]])
          end
        end

        def check_original_requirements_resolvable
          base_directory = dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files(unlock_requirement: false)

            run_update_checker
          end

          true
        rescue SharedHelpers::HelperSubprocessFailed => e
          if e.message.match?(MISSING_EXPLICIT_PLATFORM_REQ_REGEX)
            missing_extensions =
              e.message.scan(MISSING_EXPLICIT_PLATFORM_REQ_REGEX)
               .flatten.flat_map do |extension_string|
                name, requirement = extension_string.strip.split(" ", 2)
                { name: name, requirement: requirement }
              end
            raise MissingExtensions, missing_extensions
          elsif e.message.match?(MISSING_IMPLICIT_PLATFORM_REQ_REGEX) &&
                implicit_platform_reqs_satisfiable?(e.message)
            missing_extensions =
              e.message.scan(MISSING_IMPLICIT_PLATFORM_REQ_REGEX)
               .flatten.flat_map do |extension_string|
                name, requirement = extension_string.strip.split(" ", 2)
                { name: name, requirement: requirement }
              end
            raise MissingExtensions, missing_extensions
          end

          raise Dependabot::DependencyFileNotResolvable, e.message
        end

        def version_for_reqs(requirements)
          req_arrays =
            requirements
            .map { |str| Composer::Requirement.requirements_array(str) }
          potential_versions =
            req_arrays.flatten.map do |req|
              op, version = req.requirements.first
              case op
              when ">" then version.bump
              when "<" then Composer::Version.new("0.0.1")
              else version
              end
            end

          version =
            potential_versions
            .find do |v|
              req_arrays.all? { |reqs| reqs.any? { |r| r.satisfied_by?(v) } }
            end
          return unless version

          version.to_s
        end

        def update_required_extensions(additional_extensions)
          additional_extensions.each do |ext|
            composer_platform_extensions[ext.fetch(:name)] ||= []
            composer_platform_extensions[ext.fetch(:name)] +=
              [ext.fetch(:requirement)]
            composer_platform_extensions[ext.fetch(:name)] =
              composer_platform_extensions[ext.fetch(:name)].uniq
          end
        end

        def php_helper_path
          NativeHelpers.composer_helper_path(composer_version: composer_version)
        end

        def composer_version
          parsed_lockfile_or_nil = lockfile ? parsed_lockfile : nil
          @composer_version ||= Helpers.composer_version(parsed_composer_file, parsed_lockfile_or_nil)
        end

        def initial_platform
          platform_php = Helpers.capture_platform_php(parsed_composer_file)

          platform = {}
          if platform_php.is_a?(String) && requirement_valid?(platform_php)
            platform[Dependabot::Composer::Language::NAME] = [platform_php]
          end

          # NOTE: We *don't* include the require-dev PHP version in our initial
          # platform. If we fail to resolve with the PHP version specified in
          # `require` then it will be picked up in a subsequent iteration.
          requirement_php = Helpers.php_constraint(parsed_composer_file)
          return platform unless requirement_php.is_a?(String)
          return platform unless requirement_valid?(requirement_php)

          platform[Dependabot::Composer::Language::NAME] ||= []
          platform[Dependabot::Composer::Language::NAME] << requirement_php
          platform
        end

        def parsed_composer_file
          @parsed_composer_file ||= JSON.parse(composer_file.content)
        end

        def parsed_lockfile
          @parsed_lockfile ||= JSON.parse(lockfile.content)
        end

        def composer_file
          @composer_file ||=
            dependency_files.find { |f| f.name == PackageManager::MANIFEST_FILENAME }
        end

        def path_dependency_files
          @path_dependency_files ||=
            dependency_files.select { |f| f.name.end_with?("/#{PackageManager::MANIFEST_FILENAME}") }
        end

        def zipped_path_dependency_files
          @zipped_path_dependency_files ||=
            dependency_files.select { |f| f.name.end_with?(".zip", ".gitkeep") }
        end

        def lockfile
          @lockfile ||=
            dependency_files.find { |f| f.name == PackageManager::LOCKFILE_FILENAME }
        end

        def auth_json
          @auth_json ||= dependency_files.find { |f| f.name == PackageManager::AUTH_FILENAME }
        end

        def requirement_valid?(req_string)
          Composer::Requirement.requirements_array(req_string)
          true
        rescue Gem::Requirement::BadRequirementError
          false
        end

        def git_credentials
          credentials
            .select { |cred| cred["type"] == "git_source" }
            .select { |cred| cred["password"] }
        end

        def registry_credentials
          credentials
            .select { |cred| cred["type"] == PackageManager::REPOSITORY_KEY }
            .select { |cred| cred["password"] }
        end
      end
    end

    class ComposerErrorHandler
      extend T::Sig

      # Private source errors
      CURL_ERROR = /curl error 52 while downloading (?<url>.*): Empty reply from server/

      PRIVATE_SOURCE_AUTH_FAIL = [
        /Could not authenticate against (?<url>.*)/,
        /The '(?<url>.*)' URL could not be accessed \(HTTP 403\)/,
        /The "(?<url>.*)" file could not be downloaded/
      ].freeze

      REQUIREMENT_ERROR = /^(?<req>.*) is invalid, it should not contain uppercase characters/

      NO_URL = "No URL specified"

      def sanitize_uri(url)
        url = "http://#{url}" unless url.start_with?("http")
        uri = URI.parse(url)
        host = T.must(uri.host).downcase
        host.start_with?("www.") ? host[4..-1] : host
      end

      # Handles errors with specific to composer error codes
      sig { params(error: SharedHelpers::HelperSubprocessFailed).void }
      def handle_composer_error(error)
        # private source auth errors
        PRIVATE_SOURCE_AUTH_FAIL.each do |regex|
          next unless error.message.match?(regex)

          url = T.must(error.message.match(regex)).named_captures["url"]
          raise Dependabot::PrivateSourceAuthenticationFailure, sanitize_uri(url).empty? ? NO_URL : sanitize_uri(url)
        end

        # invalid requirement mentioned in manifest file
        if error.message.match?(REQUIREMENT_ERROR)
          raise DependencyFileNotResolvable,
                "Invalid requirement: #{T.must(error.message.match(REQUIREMENT_ERROR)).named_captures['req']}"
        end

        return unless error.message.match?(CURL_ERROR)

        url = T.must(error.message.match(CURL_ERROR)).named_captures["url"]
        raise PrivateSourceBadResponse, url
      end
    end
  end
end
