# frozen_string_literal: true
require "bump/file_updaters/base"
require "bump/file_fetchers/php/composer"
require "bump/shared_helpers"

module Bump
  module FileUpdaters
    module Php
      class Composer < Base
        VERSION = /[0-9]+(?:\.[a-zA-Z0-9]+)*/

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

        def required_files
          Bump::FileFetchers::Php::Composer.required_files
        end

        def composer_json
          @composer_json ||= get_original_file("composer.json")
        end

        def lockfile
          @lockfile ||= get_original_file("composer.lock")
        end

        def updated_composer_file_content
          parsed_composer_json = JSON.parse(composer_json.content)
          old_requirement = parsed_composer_json["require"][dependency.name]

          new_requirement = old_requirement.sub(VERSION) do |old_version|
            precision = old_version.split(".").count
            dependency.version.split(".").first(precision).join(".")
          end

          parsed_composer_json["require"][dependency.name] = new_requirement
          JSON.dump(parsed_composer_json)
        end

        def updated_dependency_files_content
          @updated_dependency_files_content ||=
            SharedHelpers.in_a_temporary_directory do |dir|
              File.write(File.join(dir, "composer.json"),
                         updated_composer_file_content)
              File.write(File.join(dir, "composer.lock"), lockfile.content)

              SharedHelpers.run_helper_subprocess(
                command: "php #{php_helper_path}",
                function: "update",
                args: [dir, dependency.name, dependency.version]
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
