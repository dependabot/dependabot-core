# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module JavaScript
      class Base < Dependabot::FileUpdaters::Base
        def updated_dependency_files
          updated_files = []

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          package_files.each do |file|
            next unless file_changed?(file)
            updated_files <<
              updated_file(
                file: file,
                content: updated_package_json_content(file)
              )
          end

          updated_files
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency for JS
          dependencies.first
        end

        def check_required_files
          raise "No package.json!" unless get_original_file("package.json")
        end

        def lockfile
          @lockfile ||= get_original_file(self.class::LOCKFILE_NAME)
        end

        def package_files
          dependency_files.select { |f| f.name.end_with?("package.json") }
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
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

              updated_files.fetch(lockfile.name)
            end
        end

        def write_temporary_dependency_files
          File.write(self.class::LOCKFILE_NAME, lockfile.content)
          File.write(".npmrc", npmrc_content)
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            updated_content = updated_package_json_content(file)
            updated_content = sanitized_package_json_content(updated_content)
            File.write(file.name, updated_content)
          end
        end

        # Construct a .npmrc from the passed credentials. In future we may want
        # to fetch the .npmrc and augment it, instead
        def npmrc_content
          npmrc_file = dependency_files.find { |f| f.name == ".npmrc" }

          updated_credential_lines =
            credentials.
            select { |cred| cred.key?("registry") }.
            map do |cred|
              "//#{cred.fetch('registry')}/:_authToken=#{cred.fetch('token')}"
            end

          return updated_credential_lines.join("\n") if npmrc_file.nil?

          original_content = npmrc_file.content.gsub(/^.*:_authToken=\$.*/, "")
          ([original_content] + updated_credential_lines).join("\n")
        end

        def updated_package_json_content(file)
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

        def replace_package_json_version_requirement(dependency:, file:,
                                                     content:)
          return content unless requirement_changed?(file, dependency)

          dep.requirements.
            find { |r| r[:file] == file.name }.
            fetch(:requirement)
        end

        def sanitized_package_json_content(content)
          int = 0
          content.gsub(/\{\{.*\}\}/) do
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
