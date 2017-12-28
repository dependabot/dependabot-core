# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileUpdaters
    module JavaScript
      class NpmAndYarn < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [
            /^package\.json$/,
            /^package-lock\.json$/,
            /^yarn\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          if yarn_lock && yarn_lock_changed?
            updated_files <<
              updated_file(file: yarn_lock, content: updated_yarn_lock_content)
          end

          if package_lock
            updated_files << updated_file(
              file: package_lock,
              content: updated_package_lock_content
            )
          end

          updated_files += updated_package_files

          if updated_files.sort_by(&:name) == dependency_files.sort_by(&:name)
            raise "No files have changed!"
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

        def yarn_lock
          @yarn_lock ||= get_original_file("yarn.lock")
        end

        def package_lock
          @package_lock ||= get_original_file("package-lock.json")
        end

        def package_files
          dependency_files.select { |f| f.name.end_with?("package.json") }
        end

        def yarn_lock_changed?
          yarn_lock.content != updated_yarn_lock_content
        end

        def updated_package_files
          package_files.
            select { |f| file_changed?(f) }.
            map do |f|
              updated_file(file: f, content: updated_package_json_content(f))
            end
        end

        def updated_yarn_lock_content
          @updated_yarn_lock_content ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              project_root = File.join(File.dirname(__FILE__), "../../../..")
              helper_path = File.join(project_root, "helpers/yarn/bin/run.js")

              updated_content = SharedHelpers.run_helper_subprocess(
                command: "node #{helper_path}",
                function: "update",
                args: [
                  Dir.pwd,
                  dependency.name,
                  dependency.version,
                  dependency.requirements
                ]
              ).fetch("yarn.lock")

              dependency.requirements.each do |req|
                req_string = "#{dependency.name}@#{req.fetch(:requirement)}"
                next if updated_content.include?(req_string)
                raise "Expected updated lockfile to include #{req_string}"
              end

              updated_content
            end
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.start_with?("Couldn't find any versions")
          raise Dependabot::DependencyFileNotResolvable, error.message
        end

        def updated_package_lock_content
          @updated_package_lock_content ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              project_root = File.join(File.dirname(__FILE__), "../../../..")
              helper_path = File.join(project_root, "helpers/npm/bin/run.js")

              updated_files = SharedHelpers.run_helper_subprocess(
                command: "node #{helper_path}",
                function: "update",
                args: [
                  Dir.pwd,
                  dependency.name,
                  dependency.version,
                  dependency.requirements
                ]
              )

              updated_content = updated_files.fetch("package-lock.json")
              if package_lock.content == updated_content
                raise "Expected content to change!"
              end
              updated_content
            end
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.start_with?("No matching version found")
          raise Dependabot::DependencyFileNotResolvable, error.message
        end

        def write_temporary_dependency_files
          File.write("yarn.lock", yarn_lock.content) if yarn_lock
          File.write("package-lock.json", package_lock.content) if package_lock
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

          initial_content = npmrc_file.content.gsub(/^.*:_authToken=\$.*/, "")
          initial_content = initial_content.gsub(/^_auth\s*=\s*\${.*}/) do |ln|
            cred = credentials.find { |c| c.key?("registry") }
            cred.nil? ? ln : ln.sub(/\${.*}/, cred.fetch("token"))
          end
          ([initial_content] + updated_credential_lines).join("\n")
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

        def sanitized_package_json_content(content)
          content.gsub(/\{\{.*\}\}/, "something")
        end
      end
    end
  end
end
