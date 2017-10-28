# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module JavaScript
      class Base < Dependabot::FileUpdaters::Base
        def updated_dependency_files
          [
            updated_file(
              file: package_json,
              content: updated_dependency_files_content["package.json"]
            ),
            updated_file(
              file: lockfile,
              content: updated_dependency_files_content[self.class::LOCKFILE_NAME]
            )
          ]
        end

        private

        def check_required_files
          ['package.json', self.class::LOCKFILE_NAME].each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def package_json
          @package_json ||= get_original_file("package.json")
        end

        def lockfile
          @lockfile ||= get_original_file(self.class::LOCKFILE_NAME)
        end

        def path_dependencies
          all = dependency_files.select { |f| f.name.end_with?("package.json") }
          all - [package_json]
        end

        def updated_dependency_files_content
          @updated_dependency_files_content ||=
            SharedHelpers.in_a_temporary_directory do
              File.write(self.class::LOCKFILE_NAME, lockfile.content)
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
          File.join(project_root, self.class::HELPER_PATH)
        end
      end
    end
  end
end
