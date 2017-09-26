# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Php
      class Composer < Base
        VERSION = /[0-9]+(?:\.[a-zA-Z0-9]+)*/

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
              content: updated_dependency_files_content["composer.json"]
            ),
            updated_file(
              file: lockfile,
              content: updated_dependency_files_content["composer.lock"]
            )
          ]
        end

        private

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

        def updated_dependency_files_content
          @updated_dependency_files_content ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("composer.json", composer_json.content)
              File.write("composer.lock", lockfile.content)

              SharedHelpers.run_helper_subprocess(
                command: "php #{php_helper_path}",
                function: "update",
                args: [Dir.pwd, dependency.name, dependency.version]
              )
            end
        end

        def php_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/php/bin/run.php")
        end
      end
    end
  end
end
