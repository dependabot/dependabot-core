# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/composer/file_parser"
require "dependabot/composer/file_updater"
require "dependabot/composer/version"
require "dependabot/composer/requirement"
require "dependabot/composer/native_helpers"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module Composer
    class FileUpdater
      class LockfileUpdater
        require_relative "manifest_updater"

        class MissingExtensions < StandardError
          attr_reader :extensions

          def initialize(extensions)
            @extensions = extensions
            super
          end
        end

        MISSING_EXPLICIT_PLATFORM_REQ_REGEX =
          /
            (?<=PHP\sextension\s)ext\-[^\s]+\s.*?\s(?=is|but)|
            (?<=requires\s)php(?:\-[^\s]+)?\s.*?\s(?=but)
          /x.freeze
        MISSING_IMPLICIT_PLATFORM_REQ_REGEX =
          /
            \sext\-[^\s]+\s.*?\s(?=->)|
            (?<=requires\s)php(?:\-[^\s]+)?\s.*?\s(?=->)
          /x.freeze

        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @composer_platform_extensions = initial_platform
        end

        def updated_lockfile_content
          @updated_lockfile_content ||= generate_updated_lockfile_content
        rescue MissingExtensions => e
          previous_extensions = composer_platform_extensions.dup
          update_required_extensions(e.extensions)
          raise if previous_extensions == composer_platform_extensions

          retry
        end

        private

        attr_reader :dependencies, :dependency_files, :credentials,
                    :composer_platform_extensions

        def generate_updated_lockfile_content
          base_directory = dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files

            updated_content = run_update_helper.fetch("composer.lock")

            updated_content = post_process_lockfile(updated_content)
            if lockfile.content == updated_content
              raise "Expected content to change!"
            end

            updated_content
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry_count ||= 0
          retry_count += 1
          retry if transitory_failure?(e) && retry_count <= 1
          if locked_git_dep_error?(e) && retry_count <= 1
            @lock_git_deps = false
            retry
          end

          handle_composer_errors(e)
        end

        def dependency
          # For now, we'll only ever be updating a single dependency for PHP
          dependencies.first
        end

        def run_update_helper
          SharedHelpers.with_git_configured(credentials: credentials) do
            SharedHelpers.run_helper_subprocess(
              command: "php -d memory_limit=-1 #{php_helper_path}",
              escape_command_str: false,
              function: "update",
              env: credentials_env,
              args: [
                Dir.pwd,
                dependency.name,
                dependency.version,
                git_credentials,
                registry_credentials
              ]
            )
          end
        end

        def updated_composer_json_content
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: composer_json
          ).updated_manifest_content
        end

        def transitory_failure?(error)
          return true if error.message.include?("404 Not Found")
          return true if error.message.include?("timed out")
          return true if error.message.include?("Temporary failure")

          error.message.include?("Content-Length mismatch")
        end

        def locked_git_dep_error?(error)
          error.message.start_with?("Could not authenticate against")
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/PerceivedComplexity
        def handle_composer_errors(error)
          if error.message.match?(MISSING_EXPLICIT_PLATFORM_REQ_REGEX)
            # These errors occur when platform requirements declared explicitly
            # in the composer.json aren't met.
            missing_extensions =
              error.message.scan(MISSING_EXPLICIT_PLATFORM_REQ_REGEX).
              map do |extension_string|
                name, requirement = extension_string.strip.split(" ", 2)
                { name: name, requirement: requirement }
              end
            raise MissingExtensions, missing_extensions
          elsif error.message.match?(MISSING_IMPLICIT_PLATFORM_REQ_REGEX) &&
                !library? &&
                !initial_platform.empty? &&
                implicit_platform_reqs_satisfiable?(error.message)
            missing_extensions =
              error.message.scan(MISSING_IMPLICIT_PLATFORM_REQ_REGEX).
              map do |extension_string|
                name, requirement = extension_string.strip.split(" ", 2)
                { name: name, requirement: requirement }
              end

            missing_extension = missing_extensions.find do |hash|
              existing_reqs = composer_platform_extensions[hash[:name]] || []
              version_for_reqs(existing_reqs + [hash[:requirement]])
            end

            raise MissingExtensions, [missing_extension]
          end

          if error.message.start_with?("Failed to execute git checkout")
            raise git_dependency_reference_error(error)
          end

          # Special case for Laravel Nova, which will fall back to attempting
          # to close a private repo if given invalid (or no) credentials
          if error.message.include?("github.com/laravel/nova.git")
            raise PrivateSourceAuthenticationFailure, "nova.laravel.com"
          end

          if error.message.start_with?("Failed to execute git clone")
            dependency_url =
              error.message.match(/(?:mirror|checkout) '(?<url>.*?)'/).
              named_captures.fetch("url")
            raise GitDependenciesNotReachable, dependency_url
          end

          if error.message.start_with?("Failed to clone")
            dependency_url =
              error.message.match(/Failed to clone (?<url>.*?) via/).
              named_captures.fetch("url")
            raise GitDependenciesNotReachable, dependency_url
          end

          if error.message.start_with?("Could not find a key for ACF PRO")
            raise MissingEnvironmentVariable, "ACF_PRO_KEY"
          end

          if error.message.start_with?("Unknown downloader type: npm-sign") ||
             error.message.include?("file could not be downloaded") ||
             error.message.include?("configuration does not allow connect")
            raise DependencyFileNotResolvable, error.message
          end

          if error.message.start_with?("Allowed memory size")
            raise Dependabot::OutOfMemory
          end

          if error.message.include?("403 Forbidden")
            source = error.message.match(%r{https?://(?<source>[^/]+)/}).
                     named_captures.fetch("source")
            raise PrivateSourceAuthenticationFailure, source
          end

          if error.message.include?("Argument 1 passed to Composer")
            msg = "One of your Composer plugins is not compatible with the "\
                  "latest version of Composer. Please update Composer and "\
                  "try running `composer update` to debug further."
            raise DependencyFileNotResolvable, msg
          end

          raise error
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/PerceivedComplexity

        def library?
          parsed_composer_json["type"] == "library"
        end

        def implicit_platform_reqs_satisfiable?(message)
          missing_extensions =
            message.scan(MISSING_IMPLICIT_PLATFORM_REQ_REGEX).
            map do |extension_string|
              name, requirement = extension_string.strip.split(" ", 2)
              { name: name, requirement: requirement }
            end

          missing_extensions.any? do |hash|
            existing_reqs = composer_platform_extensions[hash[:name]] || []
            version_for_reqs(existing_reqs + [hash[:requirement]])
          end
        end

        def write_temporary_dependency_files
          path_dependencies.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, file.content)
          end

          File.write("composer.json", locked_composer_json_content)
          File.write("composer.lock", lockfile.content)
          File.write("auth.json", auth_json.content) if auth_json
        end

        def locked_composer_json_content
          content = updated_composer_json_content
          content = lock_dependencies_being_updated(content)
          content = lock_git_dependencies(content) if @lock_git_deps != false
          content = add_temporary_platform_extensions(content)
          content
        end

        def add_temporary_platform_extensions(content)
          json = JSON.parse(content)

          composer_platform_extensions.each do |extension, requirements|
            json["config"] ||= {}
            json["config"]["platform"] ||= {}
            json["config"]["platform"][extension] =
              version_for_reqs(requirements)
          end

          JSON.dump(json)
        end

        def lock_dependencies_being_updated(original_content)
          dependencies.reduce(original_content) do |content, dep|
            updated_req = dep.version
            next content unless Composer::Version.correct?(updated_req)

            old_req =
              dep.requirements.find { |r| r[:file] == "composer.json" }&.
              fetch(:requirement)

            # When updating a subdep there won't be an old requirement
            next content unless old_req

            regex =
              /
                "#{Regexp.escape(dep.name)}"\s*:\s*
                "#{Regexp.escape(old_req)}"
              /x

            content.gsub(regex) do |declaration|
              declaration.gsub(%("#{old_req}"), %("#{updated_req}"))
            end
          end
        end

        def lock_git_dependencies(content)
          json = JSON.parse(content)

          FileParser::DEPENDENCY_GROUP_KEYS.each do |keys|
            next unless json[keys[:manifest]]

            json[keys[:manifest]].each do |name, req|
              next unless req.start_with?("dev-")
              next if req.include?("#")

              commit_sha = parsed_lockfile.
                           fetch(keys[:lockfile], []).
                           find { |d| d["name"] == name }&.
                           dig("source", "reference")
              json[keys[:manifest]][name] = req + "##{commit_sha}"
            end
          end

          JSON.dump(json)
        end

        def git_dependency_reference_error(error)
          ref = error.message.match(/checkout '(?<ref>.*?)'/).
                named_captures.fetch("ref")
          dependency_name =
            JSON.parse(lockfile.content).
            values_at("packages", "packages-dev").flatten(1).
            find { |dep| dep.dig("source", "reference") == ref }&.
            fetch("name")

          raise unless dependency_name

          raise GitDependencyReferenceNotFound, dependency_name
        end

        def post_process_lockfile(content)
          content = replace_patches(content)
          content = replace_content_hash(content)
          replace_platform_overrides(content)
        end

        def replace_patches(updated_content)
          content = updated_content
          %w(packages packages-dev).each do |package_type|
            JSON.parse(lockfile.content).fetch(package_type).each do |details|
              next unless details["extra"].is_a?(Hash)
              next unless (patches = details.dig("extra", "patches_applied"))

              updated_object = JSON.parse(content)
              updated_object_package =
                updated_object.
                fetch(package_type).
                find { |d| d["name"] == details["name"] }

              next unless updated_object_package

              updated_object_package["extra"] ||= {}
              updated_object_package["extra"]["patches_applied"] = patches

              content =
                JSON.pretty_generate(updated_object, indent: "    ").
                gsub(/\[\n\n\s*\]/, "[]").
                gsub(/\}\z/, "}\n")
            end
          end
          content
        end

        def replace_content_hash(content)
          existing_hash = JSON.parse(content).fetch("content-hash")
          SharedHelpers.in_a_temporary_directory do
            File.write("composer.json", updated_composer_json_content)

            content_hash =
              SharedHelpers.run_helper_subprocess(
                command: "php #{php_helper_path}",
                function: "get_content_hash",
                env: credentials_env,
                args: [Dir.pwd]
              )

            content.gsub(existing_hash, content_hash)
          end
        end

        def replace_platform_overrides(content)
          original_object = JSON.parse(lockfile.content)
          original_overrides = original_object.fetch("platform-overrides", nil)

          updated_object = JSON.parse(content)

          if original_object.key?("platform-overrides")
            updated_object["platform-overrides"] = original_overrides
          else
            updated_object.delete("platform-overrides")
          end

          JSON.pretty_generate(updated_object, indent: "    ").
            gsub(/\[\n\n\s*\]/, "[]").
            gsub(/\}\z/, "}\n")
        end

        def version_for_reqs(requirements)
          req_arrays =
            requirements.
            map { |str| Composer::Requirement.requirements_array(str) }
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
            potential_versions.
            find do |v|
              req_arrays.all? { |reqs| reqs.any? { |r| r.satisfied_by?(v) } }
            end
          raise "No matching version for #{requirements}!" unless version

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
          NativeHelpers.composer_helper_path
        end

        def credentials_env
          credentials.
            select { |c| c.fetch("type") == "php_environment_variable" }.
            map { |cred| [cred["env-key"], cred.fetch("env-value", "-")] }.
            to_h
        end

        def git_credentials
          credentials.
            select { |cred| cred.fetch("type") == "git_source" }.
            select { |cred| cred["password"] }
        end

        def registry_credentials
          credentials.
            select { |cred| cred.fetch("type") == "composer_repository" }.
            select { |cred| cred["password"] }
        end

        def initial_platform
          platform_php = parsed_composer_json.dig("config", "platform", "php")

          platform = {}
          if platform_php.is_a?(String) && requirement_valid?(platform_php)
            platform["php"] = [platform_php]
          end

          # Note: We *don't* include the require-dev PHP version in our initial
          # platform. If we fail to resolve with the PHP version specified in
          # `require` then it will be picked up in a subsequent iteration.
          requirement_php = parsed_composer_json.dig("require", "php")
          return platform unless requirement_php.is_a?(String)
          return platform unless requirement_valid?(requirement_php)

          platform["php"] ||= []
          platform["php"] << requirement_php
          platform
        end

        def requirement_valid?(req_string)
          Composer::Requirement.requirements_array(req_string)
          true
        rescue Gem::Requirement::BadRequirementError
          false
        end

        def parsed_composer_json
          @parsed_composer_json ||= JSON.parse(composer_json.content)
        end

        def parsed_lockfile
          @parsed_lockfile ||= JSON.parse(lockfile.content)
        end

        def composer_json
          @composer_json ||=
            dependency_files.find { |f| f.name == "composer.json" }
        end

        def lockfile
          @lockfile ||=
            dependency_files.find { |f| f.name == "composer.lock" }
        end

        def auth_json
          @auth_json ||= dependency_files.find { |f| f.name == "auth.json" }
        end

        def path_dependencies
          @path_dependencies ||=
            dependency_files.select { |f| f.name.end_with?("/composer.json") }
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
