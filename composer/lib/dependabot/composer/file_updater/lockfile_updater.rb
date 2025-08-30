# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/composer/file_parser"
require "dependabot/composer/file_updater"
require "dependabot/composer/version"
require "dependabot/composer/requirement"
require "dependabot/composer/native_helpers"
require "dependabot/composer/helpers"
require "dependabot/composer/update_checker/version_resolver"
require "sorbet-runtime"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module Composer
    class FileUpdater
      class LockfileUpdater
        extend T::Sig

        require_relative "manifest_updater"

        class MissingExtensions < StandardError
          extend T::Sig

          sig { returns(T::Array[T::Hash[Symbol, String]]) }
          attr_reader :extensions

          sig { params(extensions: T::Array[T::Hash[Symbol, String]]).void }
          def initialize(extensions)
            @extensions = T.let(extensions, T::Array[T::Hash[Symbol, String]])
            super
          end
        end

        MISSING_EXPLICIT_PLATFORM_REQ_REGEX =
          %r{
            (?<=PHP\sextension\s)ext\-[^\s/]+\s.*?\s(?=is|but)|
            (?<=requires\s)php(?:\-[^\s/]+)?\s.*?\s(?=but)
          }x
        MISSING_IMPLICIT_PLATFORM_REQ_REGEX =
          %r{
            (?<!with|for|by)\sext\-[^\s/]+\s.*?\s(?=->)|
            (?<=requires\s)php(?:\-[^\s/]+)?\s.*?\s(?=->)
          }x
        MISSING_ENV_VAR_REGEX = /Environment variable '(?<env_var>.[^']+)' is not set/

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @composer_platform_extensions = T.let(initial_platform, T::Hash[String, T::Array[String]])
          @lock_git_deps = T.let(true, T::Boolean)
        end

        sig { returns(String) }
        def updated_lockfile_content
          @updated_lockfile_content ||= T.let(
            generate_updated_lockfile_content,
            T.nilable(String)
          )
        rescue MissingExtensions => e
          previous_extensions = composer_platform_extensions.dup
          update_required_extensions(e.extensions)
          raise if previous_extensions == composer_platform_extensions

          retry
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Hash[String, T::Array[String]]) }
        attr_reader :composer_platform_extensions

        sig { returns(String) }
        def generate_updated_lockfile_content
          base_directory = T.must(dependency_files.first).directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files

            updated_content = run_update_helper.fetch(PackageManager::LOCKFILE_FILENAME)

            updated_content = post_process_lockfile(updated_content)
            raise "Expected content to change!" if lockfile.content == updated_content

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

        sig { returns(Dependabot::Dependency) }
        def dependency
          # For now, we'll only ever be updating a single dependency for PHP
          T.must(dependencies.first)
        end

        sig { returns(T::Hash[String, String]) }
        def run_update_helper
          SharedHelpers.with_git_configured(credentials: T.unsafe(credentials)) do
            SharedHelpers.run_helper_subprocess(
              command: "php -d memory_limit=-1 #{php_helper_path}",
              allow_unsafe_shell_command: true,
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

        sig { returns(String) }
        def updated_composer_json_content
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: composer_json
          ).updated_manifest_content
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T::Boolean) }
        def transitory_failure?(error)
          return true if error.message.include?("404 Not Found")
          return true if error.message.include?("timed out")
          return true if error.message.include?("Temporary failure")

          error.message.include?("Content-Length mismatch")
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T::Boolean) }
        def locked_git_dep_error?(error)
          error.message.start_with?("Could not authenticate against")
        end

        # TODO: Extract error handling and share between the version resolver
        #
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T.noreturn) }
        def handle_composer_errors(error)
          if error.message.match?(MISSING_EXPLICIT_PLATFORM_REQ_REGEX)
            # These errors occur when platform requirements declared explicitly
            # in the composer.json aren't met.
            missing_extensions =
              error.message.scan(MISSING_EXPLICIT_PLATFORM_REQ_REGEX)
                   .map do |extension_string|
                name, requirement = T.cast(extension_string, String).strip.split(" ", 2)
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
                name, requirement = T.cast(extension_string, String).strip.split(" ", 2)
                { name: name, requirement: requirement }
              end

            missing_extension = missing_extensions.find do |hash|
              existing_reqs = composer_platform_extensions[hash[:name]] || []
              version_for_reqs(existing_reqs + [hash[:requirement]])
            end

            raise MissingExtensions, (T.must(missing_extension).then { |ext| [ext] })
          end

          git_dependency_reference_error(error) if error.message.start_with?("Failed to execute git checkout")

          # Special case for Laravel Nova, which will fall back to attempting
          # to close a private repo if given invalid (or no) credentials
          if error.message.include?("github.com/laravel/nova.git")
            raise PrivateSourceAuthenticationFailure, "nova.laravel.com"
          end

          dependency_url = Helpers.dependency_url_from_git_clone_error(error.message)
          raise Dependabot::GitDependenciesNotReachable, dependency_url if dependency_url

          # NOTE: This matches an error message from composer plugins used to install ACF PRO
          # https://github.com/PhilippBaschke/acf-pro-installer/blob/772cec99c6ef8bc67ba6768419014cc60d141b27/src/ACFProInstaller/Exceptions/MissingKeyException.php#L14
          # https://github.com/pivvenit/acf-pro-installer/blob/f2d4812839ee2c333709b0ad4c6c134e4c25fd6d/src/Exceptions/MissingKeyException.php#L25
          if error.message.start_with?("Could not find a key for ACF PRO", "Could not find a license key for ACF PRO")
            raise MissingEnvironmentVariable, "ACF_PRO_KEY"
          end

          # NOTE: This matches error output from a composer plugin (private-composer-installer):
          # https://github.com/ffraenz/private-composer-installer/blob/8655e3da4e8f99203f13ccca33b9ab953ad30a31/src/Exception/MissingEnvException.php#L22
          match_data = error.message.match(MISSING_ENV_VAR_REGEX)
          if match_data
            env_var = match_data.named_captures.fetch("env_var")
            raise MissingEnvironmentVariable, T.must(env_var)
          end

          if error.message.start_with?("Unknown downloader type: npm-sign") ||
             error.message.include?("file could not be downloaded") ||
             error.message.include?("configuration does not allow connect")
            raise DependencyFileNotResolvable, error.message
          end

          raise Dependabot::OutOfMemory if error.message.start_with?("Allowed memory size")

          match_data = error.message.match(%r{https?://(?<source>[^/]+)/})
          if error.message.include?("403 Forbidden") && match_data
            source = match_data.named_captures.fetch("source")
            raise PrivateSourceAuthenticationFailure, source
          end

          # NOTE: This error is raised by composer v2 and includes helpful
          # information about which plugins or dependencies are not compatible
          if error.message.include?("Your requirements could not be resolved")
            raise DependencyFileNotResolvable, error.message
          end

          raise error
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(T::Boolean) }
        def library?
          parsed_composer_json["type"] == "library"
        end

        sig { params(message: String).returns(T::Boolean) }
        def implicit_platform_reqs_satisfiable?(message)
          missing_extensions =
            message.scan(MISSING_IMPLICIT_PLATFORM_REQ_REGEX)
                   .map do |extension_string|
              name, requirement = T.cast(extension_string, String).strip.split(" ", 2)
              { name: name, requirement: requirement }
            end

          missing_extensions.any? do |hash|
            existing_reqs = composer_platform_extensions[hash[:name]] || []
            version_for_reqs(existing_reqs + [hash[:requirement]])
          end
        end

        sig { void }
        def write_temporary_dependency_files
          artifact_dependencies.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, file.content)
          end

          path_dependencies.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, file.content)
          end

          File.write(PackageManager::MANIFEST_FILENAME, locked_composer_json_content)
          File.write(PackageManager::LOCKFILE_FILENAME, lockfile.content)
          File.write(PackageManager::AUTH_FILENAME, T.must(auth_json).content) if auth_json
        end

        sig { returns(String) }
        def locked_composer_json_content
          content = updated_composer_json_content
          content = lock_dependencies_being_updated(content)
          content = lock_git_dependencies(content) if @lock_git_deps != false
          content = add_temporary_platform_extensions(content)
          content
        end

        sig { params(content: String).returns(String) }
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

        sig { params(original_content: String).returns(String) }
        def lock_dependencies_being_updated(original_content)
          dependencies.reduce(original_content) do |content, dep|
            updated_req = dep.version
            next content unless Composer::Version.correct?(updated_req)

            old_req =
              dep.requirements.find { |r| r[:file] == PackageManager::MANIFEST_FILENAME }
                 &.fetch(:requirement)

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

        sig { params(content: String).returns(String) }
        def lock_git_dependencies(content)
          json = JSON.parse(content)

          FileParser::DEPENDENCY_GROUP_KEYS.each do |keys|
            next unless json[keys[:manifest]]

            json[keys[:manifest]].each do |name, req|
              next unless req.start_with?("dev-")
              next if req.include?("#")

              commit_sha = parsed_lockfile
                           .fetch(T.must(keys[:lockfile]), [])
                           .find { |d| d["name"] == name }
                           &.dig("source", "reference")
              updated_req_parts = req.split
              updated_req_parts[0] = updated_req_parts[0] + "##{commit_sha}"
              json[keys[:manifest]][name] = updated_req_parts.join(" ")
            end
          end

          JSON.dump(json)
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T.noreturn) }
        def git_dependency_reference_error(error)
          ref = error.message.match(/checkout '(?<ref>.*?)'/)
                     &.named_captures
                     &.fetch("ref")
          dependency_name =
            JSON.parse(T.must(lockfile.content))
                .values_at("packages", "packages-dev").flatten(1)
                .find { |dep| dep.dig("source", "reference") == ref }
                &.fetch("name")

          raise unless dependency_name

          raise GitDependencyReferenceNotFound, dependency_name
        end

        sig { params(updated_content: String).returns(String) }
        def replace_patches(updated_content)
          content = updated_content
          %w(packages packages-dev).each do |package_type|
            JSON.parse(T.must(lockfile.content))
                .fetch(package_type, [])
                .each do |details|
              next unless details["extra"].is_a?(Hash)
              next unless (patches = details.dig("extra", "patches_applied"))

              updated_object = JSON.parse(content)
              updated_object_package =
                updated_object
                .fetch(package_type, [])
                .find { |d| d["name"] == details["name"] }

              next unless updated_object_package

              updated_object_package["extra"] ||= {}
              updated_object_package["extra"]["patches_applied"] = patches

              content =
                JSON.pretty_generate(updated_object, indent: "    ")
                    .gsub(/\[\n\n\s*\]/, "[]")
                    .gsub(/\}\z/, "}\n")
            end
          end
          content
        end

        sig { params(content: String).returns(String) }
        def replace_content_hash(content)
          existing_hash = JSON.parse(content).fetch("content-hash")
          SharedHelpers.in_a_temporary_directory do
            File.write(PackageManager::MANIFEST_FILENAME, updated_composer_json_content)

            content_hash =
              SharedHelpers.run_helper_subprocess(
                command: "#{Language::NAME} #{php_helper_path}",
                function: "get_content_hash",
                env: credentials_env,
                args: [Dir.pwd]
              )

            content.gsub(existing_hash, content_hash)
          end
        end

        sig { params(content: String).returns(String) }
        def replace_platform_overrides(content)
          original_object = JSON.parse(T.must(lockfile.content))
          original_overrides = original_object.fetch("platform-overrides", nil)

          updated_object = JSON.parse(content)

          if original_object.key?("platform-overrides")
            updated_object["platform-overrides"] = original_overrides
          else
            updated_object.delete("platform-overrides")
          end

          JSON.pretty_generate(updated_object, indent: "    ")
              .gsub(/\[\n\n\s*\]/, "[]")
              .gsub(/\}\z/, "}\n")
        end

        sig { params(requirements: T::Array[String]).returns(String) }
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
          raise "No matching version for #{requirements}!" unless version

          version.to_s
        end

        sig { params(additional_extensions: T::Array[T::Hash[Symbol, String]]).void }
        def update_required_extensions(additional_extensions)
          additional_extensions.each do |ext|
            composer_platform_extensions[ext.fetch(:name)] ||= []
            existing_reqs = composer_platform_extensions[ext.fetch(:name)]
            composer_platform_extensions[ext.fetch(:name)] =
              T.must(existing_reqs) + [ext.fetch(:requirement)]
            composer_platform_extensions[ext.fetch(:name)] =
              T.must(composer_platform_extensions[ext.fetch(:name)]).uniq
          end
        end

        sig { returns(String) }
        def php_helper_path
          NativeHelpers.composer_helper_path(composer_version: composer_version)
        end

        sig { params(content: String).returns(String) }
        def post_process_lockfile(content)
          content = replace_patches(content)
          content = replace_content_hash(content)
          replace_platform_overrides(content)
        end

        sig { returns(String) }
        def composer_version
          @composer_version ||= T.let(
            Helpers.composer_version(parsed_composer_json, parsed_lockfile),
            T.nilable(String)
          )
        end

        sig { returns(T::Hash[String, String]) }
        def credentials_env
          credentials
            .select { |c| c.fetch("type") == "php_environment_variable" }
            .to_h { |cred| [T.cast(cred["env-key"], String), cred.fetch("env-value", "-")] }
        end

        sig { returns(T::Array[Dependabot::Credential]) }
        def git_credentials
          credentials
            .select { |cred| cred.fetch("type") == "git_source" }
            .select { |cred| cred["password"] }
        end

        sig { returns(T::Array[Dependabot::Credential]) }
        def registry_credentials
          credentials
            .select { |cred| cred.fetch("type") == PackageManager::REPOSITORY_KEY }
            .select { |cred| cred["password"] }
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def initial_platform
          platform_php = Helpers.capture_platform_php(parsed_composer_json)

          platform = {}
          platform[Language::NAME] = [platform_php] if platform_php.is_a?(String) && requirement_valid?(platform_php)

          # NOTE: We *don't* include the require-dev PHP version in our initial
          # platform. If we fail to resolve with the PHP version specified in
          # `require` then it will be picked up in a subsequent iteration.
          requirement_php = Helpers.php_constraint(parsed_composer_json)
          return platform unless requirement_php.is_a?(String)
          return platform unless requirement_valid?(requirement_php)

          platform[Language::NAME] ||= []
          platform[Language::NAME] << requirement_php
          platform
        end

        sig { params(req_string: String).returns(T::Boolean) }
        def requirement_valid?(req_string)
          Composer::Requirement.requirements_array(req_string)
          true
        rescue Gem::Requirement::BadRequirementError
          false
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_composer_json
          @parsed_composer_json ||= T.let(
            JSON.parse(T.must(composer_json.content)),
            T.nilable(T::Hash[String, T.untyped])
          )
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_lockfile
          @parsed_lockfile ||= T.let(
            JSON.parse(T.must(lockfile.content)),
            T.nilable(T::Hash[String, T.untyped])
          )
        end

        sig { returns(Dependabot::DependencyFile) }
        def composer_json
          @composer_json ||= T.let(
            T.must(dependency_files.find { |f| f.name == PackageManager::MANIFEST_FILENAME }),
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(Dependabot::DependencyFile) }
        def lockfile
          @lockfile ||= T.let(
            T.must(dependency_files.find { |f| f.name == PackageManager::LOCKFILE_FILENAME }),
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def auth_json
          @auth_json ||= T.let(
            dependency_files.find { |f| f.name == PackageManager::AUTH_FILENAME },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def artifact_dependencies
          @artifact_dependencies ||= T.let(
            dependency_files.select { |f| f.name.end_with?(".zip", ".gitkeep") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def path_dependencies
          @path_dependencies ||= T.let(
            dependency_files.select { |f| f.name.end_with?("/#{PackageManager::MANIFEST_FILENAME}") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
