# frozen_string_literal: true

require "dependabot/file_updaters/java_script/npm_and_yarn"
require "dependabot/file_parsers/java_script/npm_and_yarn"
require "dependabot/update_checkers/java_script/npm_and_yarn/registry_finder"
require "dependabot/shared_helpers"
require "dependabot/errors"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module FileUpdaters
    module JavaScript
      class NpmAndYarn
        class YarnLockfileUpdater
          require_relative "npmrc_builder"
          require_relative "package_json_updater"

          TIMEOUT_FETCHING_PACKAGE =
            %r{(?<url>.+)/(?<package>[^/]+): ETIMEDOUT}.freeze

          def initialize(dependencies:, dependency_files:, credentials:)
            @dependencies = dependencies
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def updated_yarn_lock_content(yarn_lock)
            @updated_yarn_lock_content ||= {}
            if @updated_yarn_lock_content[yarn_lock.name]
              return @updated_yarn_lock_content[yarn_lock.name]
            end

            new_content = updated_yarn_lock(yarn_lock)

            @updated_yarn_lock_content[yarn_lock.name] =
              post_process_yarn_lockfile(new_content)
          end

          private

          attr_reader :dependencies, :dependency_files, :credentials

          def dependency
            # For now, we'll only ever be updating a single dependency for JS
            dependencies.first
          end

          def updated_yarn_lock(yarn_lock)
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              updated_files =
                run_yarn_updater(path: Pathname.new(yarn_lock.name).dirname)

              updated_files.fetch("yarn.lock")
            end
          rescue SharedHelpers::HelperSubprocessFailed => error
            handle_yarn_lock_updater_error(error, yarn_lock)
          end

          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/PerceivedComplexity
          def run_yarn_updater(path:)
            SharedHelpers.with_git_configured(credentials: credentials) do
              Dir.chdir(path) do
                if dependency.top_level?
                  run_yarn_top_level_updater(path: path)
                else
                  run_yarn_subdependency_updater
                end
              end
            end
          rescue SharedHelpers::HelperSubprocessFailed => error
            raise unless error.message.include?("The registry may be down") ||
                         error.message.include?("ETIMEDOUT") ||
                         error.message.include?("ENOBUFS")

            retry_count ||= 0
            retry_count += 1
            raise if retry_count > 2

            sleep(rand(3.0..10.0)) && retry
          end
          # rubocop:enable Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/PerceivedComplexity

          def run_yarn_top_level_updater(path:)
            SharedHelpers.run_helper_subprocess(
              command: "node #{yarn_helper_path}",
              function: "update",
              args: [
                Dir.pwd,
                dependency.name,
                dependency.version,
                requirements_for_path(dependency.requirements, path)
              ]
            )
          end

          def run_yarn_subdependency_updater
            SharedHelpers.run_helper_subprocess(
              command: "node #{yarn_helper_path}",
              function: "updateSubdependency",
              args: [Dir.pwd, dependency.name]
            )
          end

          def requirements_for_path(requirements, path)
            return requirements if path.to_s == "."

            requirements.map do |r|
              next unless r[:file].start_with?("#{path}/")

              r.merge(file: r[:file].gsub(/^#{Regexp.quote("#{path}/")}/, ""))
            end.compact
          end

          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/PerceivedComplexity
          def handle_yarn_lock_updater_error(error, yarn_lock)
            if error.message.start_with?("Couldn't find any versions") ||
               error.message.include?(": Not found")

              if error.message.include?(%("#{dependency.name}"))
                # This happens if a new version has been published but npm is
                # having consistency issues. We raise a bespoke error so we can
                # capture and ignore it if we're trying to create a new PR
                # (which will be created successfully at a later date).
                raise Dependabot::InconsistentRegistryResponse, error.message
              end

              # This happens if a new version has been published that relies on
              # subdependencies that have not yet been published.
              raise if resolvable_before_update?(yarn_lock)

              msg = "Error while updating #{yarn_lock.path}:\n#{error.message}"
              raise Dependabot::DependencyFileNotResolvable, msg
            end
            if error.message.include?("Workspaces can only be enabled in priva")
              raise Dependabot::DependencyFileNotEvaluatable, error.message
            end

            if error.message.include?("Couldn't find package")
              package_name =
                error.message.match(/package "(?<package_req>.*)?"/).
                named_captures["package_req"].
                split(/(?<=\w)\@/).first
              handle_missing_package(package_name)
            end

            if error.message.match?(TIMEOUT_FETCHING_PACKAGE)
              handle_timeout(error.message)
            end
            raise
          end
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/PerceivedComplexity

          def resolvable_before_update?(yarn_lock)
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files(update_package_json: false)

              run_yarn_updater(path: Pathname.new(yarn_lock.name).dirname)
            end

            true
          rescue SharedHelpers::HelperSubprocessFailed
            false
          end

          def write_temporary_dependency_files(update_package_json: true)
            if dependency.top_level?
              write_temporary_top_level_dependency_files(
                update_package_json: update_package_json
              )
            else
              write_temporary_subdependency_dependency_files
            end
          end

          def write_temporary_top_level_dependency_files(update_package_json:)
            yarn_locks.each do |f|
              FileUtils.mkdir_p(Pathname.new(f.name).dirname)
              File.write(f.name, f.content)
            end

            File.write(".npmrc", npmrc_content)

            package_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)

              updated_content =
                if update_package_json
                  updated_package_json_content(file)
                else
                  file.content
                end

              updated_content = replace_ssh_sources(updated_content)

              # A bug prevents Yarn recognising that a directory is part of a
              # workspace if it is specified with a `./` prefix.
              updated_content = remove_workspace_path_prefixes(updated_content)

              updated_content = sanitized_package_json_content(updated_content)
              File.write(file.name, updated_content)
            end
          end

          def write_temporary_subdependency_dependency_files
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
              new_req = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'https://\1/')
              updated_content = updated_content.gsub(new_req, req)
            end

            if remove_integrity_lines?
              updated_content = remove_integrity_lines(updated_content)
            end

            updated_content
          end

          def remove_integrity_lines?
            yarn_locks.none? { |f| f.content.include?(" integrity sha") }
          end

          def remove_integrity_lines(content)
            content.lines.reject { |l| l.match?(/\s*integrity sha/) }.join
          end

          def handle_missing_package(package_name)
            return unless package_name.start_with?("@")

            missing_dep = FileParsers::JavaScript::NpmAndYarn.new(
              dependency_files: dependency_files,
              source: nil,
              credentials: credentials
            ).parse.find { |dep| dep.name == package_name }

            return unless missing_dep

            reg = UpdateCheckers::JavaScript::NpmAndYarn::RegistryFinder.new(
              dependency: missing_dep,
              credentials: credentials,
              npmrc_file: dependency_files.find { |f| f.name == ".npmrc" },
              yarnrc_file: dependency_files.find { |f| f.name == ".yarnrc" }
            ).registry

            raise PrivateSourceAuthenticationFailure, reg
          end

          def handle_timeout(message)
            url = message.match(TIMEOUT_FETCHING_PACKAGE).named_captures["url"]
            return if url.start_with?("https://registry.npmjs.org")

            package_name =
              message.match(TIMEOUT_FETCHING_PACKAGE).
              named_captures["package"].gsub("%2f", "/").gsub("%2F", "/")

            dep = FileParsers::JavaScript::NpmAndYarn.new(
              dependency_files: dependency_files,
              source: nil,
              credentials: credentials
            ).parse.find { |d| d.name == package_name }
            return unless dep

            raise PrivateSourceTimedOut, url.gsub(%r{https?://}, "")
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
              gsub(/\{\{.*?\}\}/, "something"). # {{ name }} syntax not allowed
              gsub(/(?<!\\)\\ /, " ")           # escaped whitespace not allowed
          end

          def yarn_locks
            @yarn_locks ||=
              dependency_files.
              select { |f| f.name.end_with?("yarn.lock") }
          end

          def package_files
            dependency_files.select { |f| f.name.end_with?("package.json") }
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
# rubocop:enable Metrics/ClassLength
