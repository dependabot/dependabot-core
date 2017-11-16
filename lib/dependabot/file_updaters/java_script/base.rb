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
              content: updated_dependency_files_content[lockfile.name]
            )
          ]
        end

        private

        def check_required_files
          ["package.json", self.class::LOCKFILE_NAME].each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def package_json
          @package_json ||= get_original_file("package.json")
        end

        def lockfile
          @lockfile ||= get_original_file(self.class::LOCKFILE_NAME)
        end

        def updated_dependency_files_content
          @updated_dependency_files_content ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              updated_files = SharedHelpers.run_helper_subprocess(
                command: "node #{js_helper_path}",
                function: "update",
                args: [Dir.pwd, dependency.name, dependency.version]
              )

              updated_files.
                select { |name, _| name.end_with?("package.json") }.
                each_key do |name|
                  replacement_map(name).each do |key, value|
                    updated_files[name] = updated_files[name].gsub!(key, value)
                  end
                end

              updated_files
            end
        end

        def write_temporary_dependency_files
          File.write(self.class::LOCKFILE_NAME, lockfile.content)
          dependency_files.
            select { |f| f.name.end_with?("package.json") }.
            each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(file.name, sanitized_package_json_content(file))
            end
        end

        def sanitized_package_json_content(file)
          int = 0
          file.content.gsub(/\{\{.*\}\}/) do
            int += 1
            "something-#{int}"
          end
        end

        def replacement_map(file_name)
          int = 0
          replacements = {}
          dependency_files.
            find { |f| f.name == file_name }.content.
            gsub(/\{\{.*\}\}/) do |match|
              int += 1
              replacements["something-#{int}"] = match
            end
          replacements
        end

        def js_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, self.class::HELPER_PATH)
        end
      end
    end
  end
end
