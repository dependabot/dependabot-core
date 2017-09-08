# frozen_string_literal: true
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module JavaScript
      class Yarn < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [
            /^package\.json$/,
            /^yarn\.lock$/
          ]
        end

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

        def check_required_files
          %w(package.json yarn.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def package_json
          @package_json ||= get_original_file("package.json")
        end

        def yarn_lock
          @yarn_lock ||= get_original_file("yarn.lock")
        end

        def path_dependencies
          all = dependency_files.select { |f| f.name.end_with?("package.json") }
          all - [package_json]
        end

        def updated_dependency_files_content
          @updated_dependency_files_content ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("yarn.lock", yarn_lock.content)
              File.write("package.json", package_json.content)

              path_dependencies.each do |file|
                path = file.name
                FileUtils.mkdir_p(Pathname.new(path).dirname)
                File.write(path, file.content)
              end

              SharedHelpers.run_helper_subprocess(
                command: "node #{js_helper_path}",
                function: "update",
                args: [Dir.pwd, dependency.name, dependency.version]
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
