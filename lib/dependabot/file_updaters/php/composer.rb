# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileUpdaters
    module Php
      class Composer < Base
        def self.updated_files_regex
          [
            /^composer\.json$/,
            /^composer\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          if file_changed?(composer_json)
            updated_files <<
              updated_file(
                file: composer_json,
                content: updated_composer_json_content
              )
          end

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          updated_files
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency for PHP
          dependencies.first
        end

        def check_required_files
          raise "No composer.json!" unless get_original_file("composer.json")
        end

        def composer_json
          @composer_json ||= get_original_file("composer.json")
        end

        def lockfile
          @lockfile ||= get_original_file("composer.lock")
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("composer.json", updated_composer_json_content)
              File.write("composer.lock", lockfile.content)

              updated_content =
                SharedHelpers.run_helper_subprocess(
                  command: "php #{php_helper_path}",
                  function: "update",
                  env: credentials_env,
                  args: [
                    Dir.pwd,
                    dependency.name,
                    dependency.version,
                    github_access_token
                  ]
                ).fetch("composer.lock")

              if lockfile.content == updated_content
                raise "Expected content to change!"
              end
              updated_content
            end
        rescue SharedHelpers::HelperSubprocessFailed => error
          handle_composer_errors(error)
        end

        def updated_composer_json_content
          file = composer_json

          dependencies.
            select { |dep| requirement_changed?(file, dep) }.
            reduce(file.content.dup) do |content, dep|
              updated_requirement =
                dep.requirements.find { |r| r[:file] == file.name }.
                fetch(:requirement)

              old_req =
                dep.previous_requirements.find { |r| r[:file] == file.name }.
                fetch(:requirement)

              updated_content = content.gsub(
                /"#{Regexp.escape(dep.name)}":\s*"#{Regexp.escape(old_req)}"/,
                %("#{dep.name}": "#{updated_requirement}")
              )

              raise "Expected content to change!" if content == updated_content
              updated_content
            end
        end

        def handle_composer_errors(error)
          if error.message.start_with?("Failed to execute git checkout")
            raise git_dependency_error(error)
          end
          if error.message.start_with?("Could not find a key for ACF PRO")
            raise Dependabot::MissingEnvironmentVariable, "ACF_PRO_KEY"
          end
          raise error
        end

        def git_dependency_error(error)
          ref = error.message.match(/checkout '(?<ref>.*?)'/).
                named_captures.fetch("ref")
          dependency_name =
            JSON.parse(lockfile.content).
            values_at("packages", "packages-dev").flatten(1).
            find { |dep| dep.dig("source", "reference") == ref }&.
            fetch("name")

          raise unless dependency_name
          raise Dependabot::GitDependencyReferenceNotFound, dependency_name
        end

        def php_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/php/bin/run.php")
        end

        def credentials_env
          credentials.
            select { |cred| cred.key?("env_key") }.
            map { |cred| [cred["env_key"], cred["env_value"]] }.
            to_h
        end

        def github_access_token
          credentials.
            find { |cred| cred["host"] == "github.com" }.
            fetch("password")
        end
      end
    end
  end
end
