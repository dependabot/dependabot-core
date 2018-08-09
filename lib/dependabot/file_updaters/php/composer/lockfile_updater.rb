# frozen_string_literal: true

require "dependabot/file_updaters/php/composer"
require "dependabot/utils/php/version"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileUpdaters
    module Php
      class Composer
        class LockfileUpdater
          require_relative "manifest_updater"

          def initialize(dependencies:, dependency_files:, credentials:)
            @dependencies = dependencies
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def updated_composer_lockfile_content
            updated_lockfile_content.fetch("composer.lock")
          end

          def updated_symfony_lockfile_content
            return unless symfony_lock
            updated_lockfile_content.fetch("symfony.lock")
          end

          private

          attr_reader :dependencies, :dependency_files, :credentials

          def updated_lockfile_content
            base_directory = dependency_files.first.directory
            @updated_lockfile_content ||=
              SharedHelpers.in_a_temporary_directory(base_directory) do
                write_temporary_dependency_files

                updated_lockfiles = run_update_helper

                updated_lockfiles["composer.lock"] =
                  post_process_lockfile(updated_lockfiles.fetch("composer.lock"))

                if lockfile.content == updated_lockfiles.fetch("composer.lock")
                  raise "Expected content to change!"
                end

                updated_lockfiles
              end
          rescue SharedHelpers::HelperSubprocessFailed => error
            handle_composer_errors(error)
          end

          def dependency
            # For now, we'll only ever be updating a single dependency for PHP
            dependencies.first
          end

          def run_update_helper
            SharedHelpers.with_git_configured(credentials: credentials) do
              SharedHelpers.run_helper_subprocess(
                command: "php #{php_helper_path}",
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

          # rubocop:disable Metrics/PerceivedComplexity
          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/MethodLength
          def handle_composer_errors(error)
            if error.message.start_with?("Failed to execute git checkout")
              raise git_dependency_reference_error(error)
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
            if error.message.start_with?("Unknown downloader type: npm-signatu")
              raise DependencyFileNotResolvable, error.message
            end
            if error.message.start_with?("Allowed memory size")
              raise "Composer out of memory"
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
          # rubocop:enable Metrics/PerceivedComplexity
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/MethodLength

          def write_temporary_dependency_files
            path_dependencies.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(file.name, file.content)
            end

            File.write("composer.json", locked_composer_json_content)
            File.write("composer.lock", lockfile.content)
            File.write("symfony.lock", symfony_lock.content) if symfony_lock
          end

          def locked_composer_json_content
            dependencies.
              reduce(updated_composer_json_content) do |content, dep|
                updated_req = dep.version
                next content unless Utils::Php::Version.correct?(updated_req)

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
            replace_content_hash(content)
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

          def php_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/php/bin/run.php")
          end

          def credentials_env
            credentials.
              select { |c| c.fetch("type") == "php_environment_variable" }.
              map { |cred| [cred["env-key"], cred["env-value"]] }.
              to_h
          end

          def git_credentials
            credentials.
              select { |cred| cred.fetch("type") == "git_source" }
          end

          def registry_credentials
            credentials.
              select { |cred| cred.fetch("type") == "composer_repository" }
          end

          def composer_json
            @composer_json ||=
              dependency_files.find { |f| f.name == "composer.json" }
          end

          def lockfile
            @lockfile ||=
              dependency_files.find { |f| f.name == "composer.lock" }
          end

          def symfony_lock
            @symfony_lock ||=
              dependency_files.find { |f| f.name == "symfony.lock" }
          end

          def path_dependencies
            @path_dependencies ||=
              dependency_files.select { |f| f.name.end_with?("/composer.json") }
          end
        end
      end
    end
  end
end
