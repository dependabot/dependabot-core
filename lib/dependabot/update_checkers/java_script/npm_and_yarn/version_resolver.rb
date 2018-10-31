# frozen_string_literal: true

require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/file_parsers/java_script/npm_and_yarn"
require "dependabot/file_updaters/java_script/npm_and_yarn/npmrc_builder"
require "dependabot/utils/java_script/version"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn
        class VersionResolver
          def initialize(dependency:, credentials:, dependency_files:,
                         latest_allowable_version:)
            @dependency               = dependency
            @credentials              = credentials
            @dependency_files         = dependency_files
            @latest_allowable_version = latest_allowable_version
          end

          def latest_resolvable_version
            # TODO: Check resolvability for npm lockfiles
            if package_locks.any? || shrinkwraps.any?
              return latest_allowable_version
            end

            # TODO: This is too crude. We should find the latest version that
            # won't cause those errors (by looking at the errors)
            return if peer_dependency_errors?

            latest_allowable_version
          end

          private

          attr_reader :dependency, :credentials, :dependency_files,
                      :latest_allowable_version

          def peer_dependency_errors?
            return @peer_dependency_errors if @peer_dependency_errors_checked

            @peer_dependency_errors_checked = true

            @peer_dependency_errors = run_update_check
          end

          def run_update_check
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              package_files.each do |file|
                run_yarn_checker(path: Pathname.new(file.name).dirname)
              end
            end

            false
          rescue SharedHelpers::HelperSubprocessFailed => error
            raise unless error.message.include?("incorrect peer dependency")

            true
          end

          def run_yarn_checker(path:)
            SharedHelpers.with_git_configured(credentials: credentials) do
              Dir.chdir(path) do
                SharedHelpers.run_helper_subprocess(
                  command: "node #{yarn_helper_path}",
                  function: "checkPeerDependencies",
                  args: [
                    Dir.pwd,
                    dependency.name,
                    latest_allowable_version,
                    requirements_for_path(dependency.requirements, path),
                    top_level_dependencies
                  ]
                )
              end
            end
          end

          def requirements_for_path(requirements, path)
            return requirements if path.to_s == "."

            requirements.map do |r|
              next unless r[:file].start_with?("#{path}/")

              r.merge(file: r[:file].gsub(/^#{Regexp.quote("#{path}/")}/, ""))
            end.compact
          end

          def write_temporary_dependency_files
            yarn_locks.each do |f|
              FileUtils.mkdir_p(Pathname.new(f.name).dirname)
              File.write(f.name, prepared_yarn_lockfile_content(f.content))
            end

            File.write(".npmrc", npmrc_content)

            package_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)

              updated_content = file.content
              updated_content = replace_ssh_sources(updated_content)

              # A bug prevents Yarn recognising that a directory is part of a
              # workspace if it is specified with a `./` prefix.
              updated_content = remove_workspace_path_prefixes(updated_content)

              updated_content = sanitized_package_json_content(updated_content)
              File.write(file.name, updated_content)
            end
          end

          def prepared_yarn_lockfile_content(content)
            content.gsub(/^#{Regexp.quote(dependency.name)}\@.*?\n\n/m, "")
          end

          def npmrc_content
            FileUpdaters::JavaScript::NpmAndYarn::NpmrcBuilder.new(
              credentials: credentials,
              dependency_files: dependency_files
            ).npmrc_content
          end

          # TODO: Move into a generic file preparer class that can be reused
          # between this class and the FileUpdater
          def replace_ssh_sources(content)
            updated_content = content

            git_ssh_requirements_to_swap.each do |req|
              new_req = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'https://\1/')
              updated_content = updated_content.gsub(req, new_req)
            end

            updated_content
          end

          def remove_workspace_path_prefixes(content)
            json = JSON.parse(content)
            return content unless json.key?("workspaces")

            workspace_object = json.fetch("workspaces")
            paths_array =
              if workspace_object.is_a?(Hash)
                workspace_object.values_at("packages", "nohoist").
                  flatten.compact
              elsif workspace_object.is_a?(Array) then workspace_object
              else raise "Unexpected workspace object"
              end

            paths_array.each { |path| path.gsub!(%r{^\./}, "") }

            json.to_json
          end

          def git_ssh_requirements_to_swap
            if @git_ssh_requirements_to_swap
              return @git_ssh_requirements_to_swap
            end

            @git_ssh_requirements_to_swap = []

            package_files.each do |file|
              FileParsers::JavaScript::NpmAndYarn::DEPENDENCY_TYPES.each do |t|
                JSON.parse(file.content).fetch(t, {}).each do |_, requirement|
                  next unless requirement.start_with?("git+ssh:")

                  req = requirement.split("#").first
                  @git_ssh_requirements_to_swap << req
                end
              end
            end

            @git_ssh_requirements_to_swap
          end

          def sanitized_package_json_content(content)
            content.
              gsub(/\{\{.*?\}\}/, "something"). # {{ name }} syntax not allowed
              gsub("\\ ", " ")                  # escaped whitespace not allowed
          end

          def version_class
            Utils::JavaScript::Version
          end

          # Top level dependecies are required in the peer dep checker
          # to fetch the manifests for all top level deps which may contain
          # "peerDependency" requirements
          def top_level_dependencies
            @top_level_dependencies ||= FileParsers::JavaScript::NpmAndYarn.new(
              dependency_files: dependency_files,
              source: nil,
              credentials: credentials
            ).parse.select(&:top_level?).map { |dep| dep.to_h }
          end

          def package_locks
            @package_locks ||=
              dependency_files.
              select { |f| f.name.end_with?("package-lock.json") }
          end

          def yarn_locks
            @yarn_locks ||=
              dependency_files.
              select { |f| f.name.end_with?("yarn.lock") }
          end

          def shrinkwraps
            @shrinkwraps ||=
              dependency_files.
              select { |f| f.name.end_with?("npm-shrinkwrap.json") }
          end

          def package_files
            @package_files ||=
              dependency_files.
              select { |f| f.name.end_with?("package.json") }
          end

          def yarn_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/yarn/bin/run.js")
          end
        end
      end
    end
  end
end
