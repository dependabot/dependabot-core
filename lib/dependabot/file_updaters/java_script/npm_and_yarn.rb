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

          if package_lock && package_lock_changed?
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

        UNREACHABLE_GIT = /ls-remote (?:(-h -t)|(--tags --heads)) (?<url>.*)/

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

        def package_lock_changed?
          package_lock.content != updated_package_lock_content
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

              SharedHelpers.run_helper_subprocess(
                command: "node #{helper_path}",
                function: "update",
                args: [
                  Dir.pwd,
                  dependency.name,
                  dependency.version,
                  dependency.requirements
                ]
              ).fetch("yarn.lock")
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
              if package_lock.content == updated_content &&
                 !npmrc_disables_lockfile?
                raise "Expected content to change!"
              end
              updated_content
            end
        rescue SharedHelpers::HelperSubprocessFailed => error
          handle_updater_error(error)
        end

        def handle_updater_error(error)
          if error.message.start_with?("No matching version found")
            raise Dependabot::DependencyFileNotResolvable, error.message
          end
          if error.message.include?("make sure you have the correct access") ||
             error.message.include?("Authentication failed")
            dependency_url =
              error.message.match(UNREACHABLE_GIT).
              named_captures.fetch("url")
            raise Dependabot::GitDependenciesNotReachable, dependency_url
          end
          if error.message.include?("does not contain a package.json file") &&
             error.message.include?("../deps/phoenix")
            # Special case Phoenix path dependency error. It happens because
            # Phoenix gives a path-based dependency in its lockfile but not
            # its package.json
            raise Dependabot::PathDependenciesNotReachable, ["phoenix"]
          end
          raise
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
              updated_reqs =
                dep.requirements.
                select { |r| r[:file] == file.name }.
                reject { |r| dep.previous_requirements.include?(r) }

              updated_reqs.each do |new_req|
                old_req =
                  dep.previous_requirements.
                  select { |r| r[:file] == file.name }.
                  find { |r| r[:groups] == new_req[:groups] }

                new_content = update_package_json_declaration(
                  package_json_content: content,
                  dependency_name: dep.name,
                  old_req: old_req,
                  new_req: new_req
                )

                raise "Expected content to change!" if content == new_content
                content = new_content
              end

              content
            end
        end

        def update_package_json_declaration(package_json_content:, new_req:,
                                            dependency_name:, old_req:)
          original_line = declaration_line(
            dependency_name: dependency_name,
            dependency_req: old_req,
            content: package_json_content
          )

          replacement_line = replacement_declaration_line(
            original_line: original_line,
            old_req: old_req,
            new_req: new_req
          )

          package_json_content.sub(original_line, replacement_line)
        end

        def declaration_line(dependency_name:, dependency_req:, content:)
          git_dependency = dependency_req.dig(:source, :type) == "git"

          unless git_dependency
            requirement = dependency_req.fetch(:requirement)
            return content.match(/"#{Regexp.escape(dependency_name)}":\s*
                                  "#{Regexp.escape(requirement)}"/x).to_s
          end

          username, repo = dependency_req.dig(:source, :url).split("/").last(2)

          content.match(
            %r{"#{Regexp.escape(dependency_name)}":\s*
               "#{Regexp.escape(username)}/#{Regexp.escape(repo)}.*"}x
          ).to_s
        end

        def replacement_declaration_line(original_line:, old_req:, new_req:)
          git_dependency = new_req.dig(:source, :type) == "git"

          unless git_dependency
            return original_line.gsub(
              %("#{old_req.fetch(:requirement)}"),
              %("#{new_req.fetch(:requirement)}")
            )
          end

          if git_dependency && original_line.include?("semver:")
            return original_line.gsub(
              %(semver:#{old_req.fetch(:requirement)}"),
              %(semver:#{new_req.fetch(:requirement)}")
            )
          end

          original_line.gsub(
            %(\##{old_req.dig(:source, :ref)}"),
            %(\##{new_req.dig(:source, :ref)}")
          )
        end

        def npmrc_disables_lockfile?
          npmrc_content.match?(/^package-lock\s*=\s*false/)
        end

        def sanitized_package_json_content(content)
          content.gsub(/\{\{.*\}\}/, "something")
        end
      end
    end
  end
end
