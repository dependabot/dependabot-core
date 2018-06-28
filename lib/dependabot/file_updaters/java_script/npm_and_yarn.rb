# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/file_parsers/java_script/npm_and_yarn"
require "dependabot/shared_helpers"
require "dependabot/errors"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module FileUpdaters
    module JavaScript
      class NpmAndYarn < Dependabot::FileUpdaters::Base
        require_relative "npm_and_yarn/npmrc_builder"
        require_relative "npm_and_yarn/package_json_updater"

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
          package_files.map do |file|
            updated_content = updated_package_json_content(file)
            next if updated_content == file.content
            updated_file(file: file, content: updated_content)
          end.compact
        end

        def updated_yarn_lock_content
          return @updated_yarn_lock_content if @updated_yarn_lock_content
          new_content =
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              configure_git_to_use_https_with_credentials
              updated_files = run_yarn_updater

              updated_files.fetch("yarn.lock")
            end
          @updated_yarn_lock_content = post_process_yarn_lockfile(new_content)
        rescue SharedHelpers::HelperSubprocessFailed => error
          handle_yarn_lock_updater_error(error)
        ensure
          reset_git_config
        end

        def updated_package_lock_content
          return package_lock.content if npmrc_disables_lockfile?

          @updated_package_lock_content ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files(lock_git_deps: true)

              configure_git_to_use_https_with_credentials
              updated_files = run_npm_updater

              updated_content = updated_files.fetch("package-lock.json")
              updated_content = post_process_npm_lockfile(updated_content)
              raise "No change!" if package_lock.content == updated_content
              updated_content
            end
        rescue SharedHelpers::HelperSubprocessFailed => error
          handle_package_lock_updater_error(error)
        ensure
          reset_git_config
        end

        def run_yarn_updater
          SharedHelpers.run_helper_subprocess(
            command: "node #{yarn_helper_path}",
            function: "update",
            args: [
              Dir.pwd,
              dependency.name,
              dependency.version,
              dependency.requirements
            ]
          )
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.include?("The registry may be down")
          retry_count ||= 0
          retry_count += 1
          raise if retry_count > 2
          sleep(rand(3.0..10.0)) && retry
        end

        def run_npm_updater
          SharedHelpers.run_helper_subprocess(
            command: "node #{npm_helper_path}",
            function: "update",
            args: [
              Dir.pwd,
              dependency.name,
              dependency.version,
              dependency.requirements
            ]
          )
        end

        def configure_git_to_use_https_with_credentials
          configure_git_to_use_https
          set_git_credentials
        end

        def configure_git_to_use_https
          run_shell_command(
            'git config --global --replace-all url."https://github.com/".'\
            "insteadOf ssh://git@github.com/ && "\
            'git config --global --add url."https://github.com/".'\
            "insteadOf ssh://git@github.com: && "\
            'git config --global --add url."https://github.com/".'\
            "insteadOf git@github.com: && "\
            'git config --global --add url."https://github.com/".'\
            "insteadOf git@github.com/ && "\
            'git config --global --add url."https://github.com/".'\
            "insteadOf git://github.com/"
          )
        end

        def set_git_credentials
          run_shell_command(
            "git config --global --replace-all credential.helper "\
            "'store --file=#{Dir.pwd}/git.store'"
          )

          git_store_content = ""
          credentials.each do |cred|
            next unless cred["type"] == "git_source"
            authenticated_url =
              "https://#{cred.fetch('username')}:#{cred.fetch('password')}"\
              "@#{cred.fetch('host')}"

            git_store_content += authenticated_url + "\n"
          end

          File.write("git.store", git_store_content)
        end

        def reset_git_config
          run_shell_command(
            'git config --global --remove-section url."https://github.com/" '\
            "&& git config --global --remove-section credential"
          )
        end

        def run_shell_command(command)
          raw_response = nil
          IO.popen(command, err: %i(child out)) do |process|
            raw_response = process.read
          end

          # Raise an error with the output from the shell session if the command
          # returns a non-zero status
          return if $CHILD_STATUS.success?
          raise SharedHelpers::HelperSubprocessFailed.new(
            raw_response,
            command
          )
        end

        def handle_yarn_lock_updater_error(error)
          if error.message.start_with?("Couldn't find any versions") ||
             error.message.include?(": Not found")
            raise if error.message.include?(%("#{dependency.name}"))
            raise Dependabot::DependencyFileNotResolvable, error.message
          end
          raise
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        def handle_package_lock_updater_error(error)
          raise if error.message.include?("#{dependency.name}@")
          if error.message.start_with?("No matching version", "404 Not Found")
            raise Dependabot::DependencyFileNotResolvable, error.message
          end
          if error.message.include?("did not match any file(s) known to git") ||
             error.message.include?("Non-registry package missing package.j") ||
             error.message.include?("Cannot read property 'match' of undefined")
            msg = "Error while generating package-lock.json:\n#{error.message}"
            raise Dependabot::DependencyFileNotResolvable, msg
          end
          if error.message.include?("fatal: reference is not a tree")
            ref = error.message.match(/a tree: (?<ref>.*)/).
                  named_captures.fetch("ref")
            dep = find_npm_lockfile_dependency_with_ref(ref)
            raise unless dep
            raise Dependabot::GitDependencyReferenceNotFound, dep.fetch(:name)
          end
          if error.message.include?("make sure you have the correct access") ||
             error.message.include?("Authentication failed")
            dependency_url =
              error.message.match(UNREACHABLE_GIT).
              named_captures.fetch("url")
            raise if dependency_url.start_with?("ssh://")
            raise Dependabot::GitDependenciesNotReachable, dependency_url
          end
          raise
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength

        def write_temporary_dependency_files(lock_git_deps: false)
          File.write("yarn.lock", yarn_lock.content) if yarn_lock
          File.write("package-lock.json", package_lock.content) if package_lock
          File.write(".npmrc", npmrc_content)
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            updated_content = updated_package_json_content(file)

            # When updating a package-lock.json we have to manually lock all
            # git dependencies, otherwise npm will (unhelpfully) update them
            updated_content = lock_git_deps(updated_content) if lock_git_deps
            updated_content = replace_ssh_sources(updated_content)

            # A bug prevents Yarn recognising that a directory is part of a
            # workspace if it is specified with a `./` prefix.
            updated_content = remove_workspace_path_prefixes(updated_content)

            updated_content = sanitized_package_json_content(updated_content)
            File.write(file.name, updated_content)
          end
        end

        def lock_git_deps(content)
          return content if git_dependencies_to_lock.empty?
          types = FileParsers::JavaScript::NpmAndYarn::DEPENDENCY_TYPES

          json = JSON.parse(content)
          types.each do |type|
            json.fetch(type, {}).each do |nm, _|
              updated_version = git_dependencies_to_lock[nm]
              next unless updated_version
              json[type][nm] = git_dependencies_to_lock[nm]
            end
          end

          json.to_json
        end

        def git_dependencies_to_lock
          return {} unless package_lock
          return @git_dependencies_to_lock if @git_dependencies_to_lock

          @git_dependencies_to_lock = {}
          dependency_names = dependencies.map(&:name)

          FileParsers::JavaScript::NpmAndYarn::DEPENDENCY_TYPES.each do |t|
            JSON.parse(package_lock.content).fetch(t, {}).each do |nm, details|
              next if dependency_names.include?(nm)
              next unless details["version"]
              next unless details["version"].start_with?("git")
              @git_dependencies_to_lock[nm] = details["version"]
            end
          end
          @git_dependencies_to_lock
        end

        def replace_ssh_sources(content)
          updated_content = content

          git_ssh_requirements_to_swap.each do |req|
            updated_req = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'https://\1/')
            updated_content = updated_content.gsub(req, updated_req)
          end

          updated_content
        end

        def remove_workspace_path_prefixes(content)
          json = JSON.parse(content)
          return content unless json.key?("workspaces")

          workspace_object = json.fetch("workspaces")
          paths_array =
            if workspace_object.is_a?(Hash) then workspace_object["packages"]
            elsif workspace_object.is_a?(Array) then workspace_object
            else raise "Unexpected workspace object"
            end

          paths_array.each { |path| path.gsub!(%r{^\./}, "") }

          json.to_json
        end

        def git_ssh_requirements_to_swap
          return @git_ssh_requirements_to_swap if @git_ssh_requirements_to_swap

          git_dependencies =
            dependencies.
            select do |dep|
              dep.requirements.any? { |r| r.dig(:source, :type) == "git" }
            end

          @git_ssh_requirements_to_swap = []

          package_files.each do |file|
            FileParsers::JavaScript::NpmAndYarn::DEPENDENCY_TYPES.each do |t|
              JSON.parse(file.content).fetch(t, {}).each do |nm, requirement|
                next unless git_dependencies.map(&:name).include?(nm)
                next unless requirement.start_with?("git+ssh:")
                req = requirement.split("#").first
                @git_ssh_requirements_to_swap << req
              end
            end
          end

          @git_ssh_requirements_to_swap
        end

        def post_process_yarn_lockfile(lockfile_content)
          updated_content = lockfile_content

          git_ssh_requirements_to_swap.each do |req|
            updated_req = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'https://\1/')
            updated_content = updated_content.gsub(updated_req, req)
          end

          updated_content
        end

        def post_process_npm_lockfile(lockfile_content)
          updated_content = lockfile_content

          git_ssh_requirements_to_swap.each do |req|
            new_req = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'git+https://\1/')
            old_req = req.gsub(%r{git@(.*?)[:/]}, 'git@\1/')
            updated_content = updated_content.gsub(new_req, old_req)
          end

          updated_content
        end

        def find_npm_lockfile_dependency_with_ref(ref)
          flatten_dependencies = lambda { |obj|
            deps = []
            obj["dependencies"]&.each do |name, details|
              deps << { name: name, version: details["version"] }
              deps += flatten_dependencies.call(details)
            end
            deps
          }

          deps = flatten_dependencies.call(JSON.parse(package_lock.content))
          deps.find { |dep| dep[:version].end_with?("##{ref}") }
        end

        def npmrc_content
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content
        end

        def updated_package_json_content(file)
          @updated_package_json_content ||= {}
          @updated_package_json_content[file.name] ||=
            PackageJsonUpdater.new(
              package_json: file,
              dependencies: dependencies
            ).updated_package_json.content
        end

        def npmrc_disables_lockfile?
          npmrc_content.match?(/^package-lock\s*=\s*false/)
        end

        def sanitized_package_json_content(content)
          content.
            gsub(/\{\{.*\}\}/, "something"). # {{ name }} syntax not allowed
            gsub("\\ ", " ")                 # escaped whitespace not allowed
        end

        def yarn_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/yarn/bin/run.js")
        end

        def npm_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/npm/bin/run.js")
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
