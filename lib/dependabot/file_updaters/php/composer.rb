# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

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
          [
            updated_file(
              file: composer_json,
              content: updated_composer_json_content
            ),
            updated_file(
              file: lockfile,
              content: updated_lockfile_content
            )
          ]
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency for PHP
          dependencies.first
        end

        def check_required_files
          %w(composer.json composer.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def composer_json
          @composer_json ||= get_original_file("composer.json")
        end

        def lockfile
          @lockfile ||= get_original_file("composer.lock")
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

        def updated_lockfile_content
          raw_content = updated_dependency_files_content["composer.lock"]

          replaced_urls.each do |url|
            raw_content.gsub!(
              "https://github.com/#{url}",
              "git@github.com:#{url}"
            )
          end

          raw_content
        end

        def prepared_composer_json_content
          updated_composer_json_content.
            gsub("git@github.com:", "https://github.com/")
        end

        def prepared_lockfile_content
          lockfile.content.gsub("git@github.com:", "https://github.com/")
        end

        def updated_dependency_files_content
          @updated_dependency_files_content ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("composer.json", prepared_composer_json_content)
              File.write("composer.lock", prepared_lockfile_content)

              SharedHelpers.run_helper_subprocess(
                command: "php #{php_helper_path}",
                function: "update",
                args: [
                  Dir.pwd,
                  dependency.name,
                  dependency.version,
                  github_access_token
                ]
              )
            end
        end

        def replaced_urls
          lockfile.content.scan(/"git@github\.com:(.*?)"/).flatten
        end

        def php_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/php/bin/run.php")
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
