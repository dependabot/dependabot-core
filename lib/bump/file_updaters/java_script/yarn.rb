# frozen_string_literal: true
require "bump/file_updaters/base"
require "bump/file_fetchers/java_script/yarn"
require "bump/shared_helpers"

module Bump
  module FileUpdaters
    module JavaScript
      class Yarn < Bump::FileUpdaters::Base
        def updated_dependency_files
          [
            updated_file(
              file: package_json,
              content: updated_dependency_files_content["package.json"]
            ),
            updated_file(
              file: yarn_lock,
              content: updated_dependency_files_content["yarn.lock"]
            )
          ]
        end

        private

        def required_files
          Bump::FileFetchers::JavaScript::Yarn.required_files
        end

        def package_json
          @package_json ||= get_original_file("package.json")
        end

        def yarn_lock
          @yarn_lock ||= get_original_file("yarn.lock")
        end

        def updated_dependency_files_content
          @updated_dependency_files_content ||=
            SharedHelpers.in_a_temporary_directory do |dir|
              File.write(File.join(dir, "yarn.lock"), yarn_lock.content)
              File.write(File.join(dir, "package.json"), package_json.content)

              SharedHelpers.run_helper_subprocess(
                command: "node #{js_helper_path}",
                function: "update",
                args: [dir, dependency.name, dependency.version]
              )
            end
        end

        def js_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/javascript/bin/run.js")
        end
      end
    end
  end
end
