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

        def path_dependencies
          @path_dependencies ||=
            dependency_files.select { |f| f.name.end_with?("/composer.json") }
        end

        def updated_lockfile_content
          base_directory = dependency_files.first.directory
          @updated_lockfile_content ||=
            SharedHelpers.in_a_temporary_directory(base_directory) do
              write_temporary_dependency_files

              updated_content =
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
                ).fetch("composer.lock")

              updated_content = replace_patches(updated_content)
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

          updated_content =
            dependencies.
            select { |dep| requirement_changed?(file, dep) }.
            reduce(file.content.dup) do |content, dep|
              updated_req =
                dep.requirements.find { |r| r[:file] == file.name }.
                fetch(:requirement)

              old_req =
                dep.previous_requirements.find { |r| r[:file] == file.name }.
                fetch(:requirement)

              regex =
                /"#{Regexp.escape(dep.name)}"\s*:\s*"#{Regexp.escape(old_req)}"/

              updated_content = content.gsub(regex) do |declaration|
                declaration.gsub(%("#{old_req}"), %("#{updated_req}"))
              end

              raise "Expected content to change!" if content == updated_content
              updated_content
            end

          update_git_sources(updated_content)
        end

        def update_git_sources(content)
          # We need to replace `git` types with `vcs` so that auth works.
          # Spacing is important so we don't accidentally replace the source for
          # "type": "package" dependencies.
          content.gsub(
            /^      "type"\s*:\s*"git"/,
            '      "type": "vcs"'
          ).gsub(
            /^            "type"\s*:\s*"git"/,
            '            "type": "vcs"'
          )
        end

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
          if error.message.start_with?("Unknown downloader type: npm-signature")
            raise DependencyFileNotResolvable, error.message
          end
          raise error
        end

        def write_temporary_dependency_files
          path_dependencies.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, file.content)
          end

          File.write("composer.json", updated_composer_json_content)
          File.write("composer.lock", lockfile.content)
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

        def php_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/php/bin/run.php")
        end

        def credentials_env
          credentials.
            select { |cred| cred.key?("env-key") }.
            map { |cred| [cred["env-key"], cred["env-value"]] }.
            to_h
        end

        def git_credentials
          credentials.
            select { |cred| cred["type"] == "git_source" }
        end

        def registry_credentials
          credentials.select { |cred| cred.key?("registry") }
        end
      end
    end
  end
end
