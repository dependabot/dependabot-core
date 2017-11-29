# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module JavaScript
      class Base < Dependabot::FileUpdaters::Base
        def updated_dependency_files
          dependency_files.
            select { |f| updated_contents[f.name] }.
            reject { |f| f.content == updated_contents[f.name] }.
            map { |f| updated_file(file: f, content: updated_contents[f.name]) }
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency for JS
          dependencies.first
        end

        def check_required_files
          ["package.json", self.class::LOCKFILE_NAME].each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def lockfile
          @lockfile ||= get_original_file(self.class::LOCKFILE_NAME)
        end

        def updated_contents
          @updated_contents ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              updated_files = SharedHelpers.run_helper_subprocess(
                command: "node #{js_helper_path}",
                function: "update",
                args: [
                  Dir.pwd,
                  dependency.name,
                  dependency.version,
                  dependency.requirements
                ]
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
          File.write(".npmrc", npmrc_content)
          dependency_files.
            select { |f| f.name.end_with?("package.json") }.
            each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(file.name, sanitized_package_json_content(file))
            end
        end

        # Construct a .npmrc from the passed credentials. In future we may want
        # to fetch the .npmrc and augment it, instead
        def npmrc_content
          credentials.
            select { |cred| cred.key?("registry") }.
            map do |cred|
              "//#{cred.fetch('registry')}/:_authToken=#{cred.fetch('token')}"
            end.join("\n")
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
