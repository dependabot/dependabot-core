# frozen_string_literal: true

require "uri"

require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/shared_helpers"
require "dependabot/errors"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module NpmAndYarn
    class FileUpdater
      class YarnLockfileUpdater
        require_relative "npmrc_builder"
        require_relative "package_json_updater"

        def initialize(dependencies:, dependency_files:, repo_contents_path:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        def updated_yarn_lock_content(yarn_lock)
          @updated_yarn_lock_content ||= {}
          return @updated_yarn_lock_content[yarn_lock.name] if @updated_yarn_lock_content[yarn_lock.name]

          new_content = updated_yarn_lock(yarn_lock)

          @updated_yarn_lock_content[yarn_lock.name] =
            post_process_yarn_lockfile(new_content)
        end

        private

        attr_reader :dependencies, :dependency_files, :repo_contents_path, :credentials

        UNREACHABLE_GIT = /ls-remote --tags --heads (?<url>.*)/
        TIMEOUT_FETCHING_PACKAGE = %r{(?<url>.+)/(?<package>[^/]+): ETIMEDOUT}
        INVALID_PACKAGE = /Can't add "(?<package_req>.*)": invalid/

        def top_level_dependencies
          dependencies.select(&:top_level?)
        end

        def sub_dependencies
          dependencies.reject(&:top_level?)
        end

        def updated_yarn_lock(yarn_lock)
          base_dir = dependency_files.first.directory
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            write_temporary_dependency_files(yarn_lock)
            lockfile_name = Pathname.new(yarn_lock.name).basename.to_s
            path = Pathname.new(yarn_lock.name).dirname.to_s
            updated_files = run_current_yarn_update(
              path: path,
              yarn_lock: yarn_lock
            )
            updated_files.fetch(lockfile_name)
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_yarn_lock_updater_error(e, yarn_lock)
        end

        def run_current_yarn_update(path:, yarn_lock:)
          top_level_dependency_updates = top_level_dependencies.map do |d|
            {
              name: d.name,
              version: d.version,
              requirements: requirements_for_path(d.requirements, path)
            }
          end

          run_yarn_updater(
            path: path,
            yarn_lock: yarn_lock,
            top_level_dependency_updates: top_level_dependency_updates
          )
        end

        def run_previous_yarn_update(path:, yarn_lock:)
          previous_top_level_dependencies = top_level_dependencies.map do |d|
            {
              name: d.name,
              version: d.previous_version,
              requirements: requirements_for_path(
                d.previous_requirements, path
              )
            }
          end

          run_yarn_updater(
            path: path,
            yarn_lock: yarn_lock,
            top_level_dependency_updates: previous_top_level_dependencies
          )
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def run_yarn_updater(path:, yarn_lock:, top_level_dependency_updates:)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              if top_level_dependency_updates.any?
                if Helpers.yarn_berry?(yarn_lock)
                  run_yarn_berry_top_level_updater(top_level_dependency_updates: top_level_dependency_updates,
                                                   yarn_lock: yarn_lock)
                else

                  run_yarn_top_level_updater(
                    top_level_dependency_updates: top_level_dependency_updates
                  )
                end
              elsif Helpers.yarn_berry?(yarn_lock)
                run_yarn_berry_subdependency_updater(yarn_lock: yarn_lock)
              else
                run_yarn_subdependency_updater(yarn_lock: yarn_lock)
              end
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          names = dependencies.map(&:name)
          package_missing = names.any? do |name|
            e.message.include?("find package \"#{name}")
          end

          raise unless e.message.include?("The registry may be down") ||
                       e.message.include?("ETIMEDOUT") ||
                       e.message.include?("ENOBUFS") ||
                       package_missing

          retry_count ||= 0
          retry_count += 1
          raise if retry_count > 2

          sleep(rand(3.0..10.0)) && retry
        end

        # rubocop:enable Metrics/PerceivedComplexity

        def run_yarn_berry_top_level_updater(top_level_dependency_updates:, yarn_lock:)
          write_temporary_dependency_files(yarn_lock)
          # If the requirements have changed, it means we've updated the
          # package.json file(s), and we can just run yarn install to get the
          # lockfile in the right state. Otherwise we'll need to manually update
          # the lockfile.

          if top_level_dependency_updates.all? { |dep| requirements_changed?(dep[:name]) }
            Helpers.run_yarn_command("yarn install #{yarn_berry_args}".strip)
          else
            updates = top_level_dependency_updates.collect do |dep|
              dep[:name]
            end

            Helpers.run_yarn_command(
              "yarn up -R #{updates.join(' ')} #{yarn_berry_args}".strip,
              fingerprint: "yarn up -R <dependency_names> #{yarn_berry_args}".strip
            )
          end
          { yarn_lock.name => File.read(yarn_lock.name) }
        end

        def requirements_changed?(dependency_name)
          dep = top_level_dependencies.first { |d| d.name == dependency_name }
          dep.requirements != dep.previous_requirements
        end

        def run_yarn_berry_subdependency_updater(yarn_lock:)
          dep = sub_dependencies.first
          update = "#{dep.name}@#{dep.version}"

          commands = [
            ["yarn add #{update} #{yarn_berry_args}".strip, "yarn add <update> #{yarn_berry_args}".strip],
            ["yarn dedupe #{dep.name} #{yarn_berry_args}".strip, "yarn dedupe <dep_name> #{yarn_berry_args}".strip],
            ["yarn remove #{dep.name} #{yarn_berry_args}".strip, "yarn remove <dep_name> #{yarn_berry_args}".strip]
          ]

          Helpers.run_yarn_commands(*commands)
          { yarn_lock.name => File.read(yarn_lock.name) }
        end

        def yarn_berry_args
          Helpers.yarn_berry_args
        end

        def run_yarn_top_level_updater(top_level_dependency_updates:)
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "yarn:update",
            args: [
              Dir.pwd,
              top_level_dependency_updates
            ]
          )
        end

        def run_yarn_subdependency_updater(yarn_lock:)
          lockfile_name = Pathname.new(yarn_lock.name).basename.to_s
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "yarn:updateSubdependency",
            args: [Dir.pwd, lockfile_name, sub_dependencies.first.to_h]
          )
        end

        def requirements_for_path(requirements, path)
          return requirements if path.to_s == "."

          requirements.filter_map do |r|
            next unless r[:file].start_with?("#{path}/")

            r.merge(file: r[:file].gsub(/^#{Regexp.quote("#{path}/")}/, ""))
          end
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        def handle_yarn_lock_updater_error(error, yarn_lock)
          error_message = error.message
          # Invalid package: When package.json doesn't include a name or version
          # Local path error: When installing a git dependency which
          # is using local file paths for sub-dependencies (e.g. unbuilt yarn
          # workspace project)
          sub_dep_local_path_err = 'Package "" refers to a non-existing file'
          if error_message.match?(INVALID_PACKAGE) ||
             error_message.start_with?(sub_dep_local_path_err)
            raise_resolvability_error(error_message, yarn_lock)
          end

          if error_message.include?("Couldn't find package")
            package_name = error_message.match(/package "(?<package_req>.*?)"/).
                           named_captures["package_req"].
                           split(/(?<=\w)\@/).first
            sanitized_name = sanitize_package_name(package_name)
            sanitized_error = error_message.gsub(package_name, sanitized_name)
            handle_missing_package(sanitized_name, sanitized_error, yarn_lock)
          end

          if error_message.match?(%r{/[^/]+: Not found})
            package_name = error_message.
                           match(%r{/(?<package_name>[^/]+): Not found}).
                           named_captures["package_name"]
            sanitized_name = sanitize_package_name(package_name)
            sanitized_error = error_message.gsub(package_name, sanitized_name)
            handle_missing_package(sanitized_name, sanitized_error, yarn_lock)
          end

          # TODO: Move this logic to the version resolver and check if a new
          # version and all of its subdependencies are resolvable

          # Make sure the error in question matches the current list of
          # dependencies or matches an existing scoped package, this handles the
          # case where a new version (e.g. @angular-devkit/build-angular) relies
          # on a added dependency which hasn't been published yet under the same
          # scope (e.g. @angular-devkit/build-optimizer)
          #
          # This seems to happen when big monorepo projects publish all of their
          # packages sequentially, which might take enough time for Dependabot
          # to hear about a new version before all of its dependencies have been
          # published
          #
          # OR
          #
          # This happens if a new version has been published but npm is having
          # consistency issues and the version isn't fully available on all
          # queries
          if error_message.start_with?("Couldn't find any versions") &&
             dependencies_in_error_message?(error_message) &&
             resolvable_before_update?(yarn_lock)

            # Raise a bespoke error so we can capture and ignore it if
            # we're trying to create a new PR (which will be created
            # successfully at a later date)
            raise Dependabot::InconsistentRegistryResponse, error_message
          end

          if error_message.include?("Workspaces can only be enabled in priva")
            raise Dependabot::DependencyFileNotEvaluatable, error_message
          end

          if error_message.match?(UNREACHABLE_GIT)
            dependency_url = error_message.match(UNREACHABLE_GIT).
                             named_captures.fetch("url")

            raise Dependabot::GitDependenciesNotReachable, dependency_url
          end

          handle_timeout(error_message, yarn_lock) if error_message.match?(TIMEOUT_FETCHING_PACKAGE)

          if error_message.start_with?("Couldn't find any versions") ||
             error_message.include?(": Not found")

            raise_resolvability_error(error_message, yarn_lock) unless resolvable_before_update?(yarn_lock)

            # Dependabot has probably messed something up with the update and we
            # want to hear about it
            raise error
          end

          raise error
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength

        def resolvable_before_update?(yarn_lock)
          @resolvable_before_update ||= {}
          return @resolvable_before_update[yarn_lock.name] if @resolvable_before_update.key?(yarn_lock.name)

          @resolvable_before_update[yarn_lock.name] =
            begin
              base_dir = dependency_files.first.directory
              SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
                write_temporary_dependency_files(yarn_lock, update_package_json: false)
                path = Pathname.new(yarn_lock.name).dirname.to_s
                run_previous_yarn_update(path: path, yarn_lock: yarn_lock)
              end

              true
            rescue SharedHelpers::HelperSubprocessFailed
              false
            end
        end

        def dependencies_in_error_message?(message)
          names = dependencies.map { |dep| dep.name.split("/").first }
          # Example format: Couldn't find any versions for
          # "@dependabot/dummy-pkg-b" that matches "^1.3.0"
          names.any? do |name|
            message.match?(%r{"#{Regexp.quote(name)}["\/]})
          end
        end

        def write_temporary_dependency_files(yarn_lock, update_package_json: true)
          write_lockfiles

          if Helpers.yarn_berry?(yarn_lock)
            File.write(".yarnrc.yml", yarnrc_yml_content) if yarnrc_yml_file
          else
            File.write(".npmrc", npmrc_content) unless Helpers.yarn_berry?(yarn_lock)
            File.write(".yarnrc", yarnrc_content) if yarnrc_specifies_private_reg?
          end

          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)

            updated_content =
              if update_package_json && top_level_dependencies.any?
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

        def write_lockfiles
          yarn_locks.each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, f.content)
          end
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
            else
              raise "Unexpected workspace object"
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
            NpmAndYarn::FileParser::DEPENDENCY_TYPES.each do |t|
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

          # Enforce https for most common hostnames
          updated_content = updated_content.gsub(
            %r{http://(.*?(?:yarnpkg\.com|npmjs\.org|npmjs\.com))/},
            'https://\1/'
          )

          updated_content = remove_integrity_lines(updated_content) if remove_integrity_lines?

          updated_content
        end

        def remove_integrity_lines?
          yarn_locks.none? { |f| f.content.include?(" integrity sha") }
        end

        def remove_integrity_lines(content)
          content.lines.reject { |l| l.match?(/\s*integrity sha/) }.join
        end

        def lockfile_dependencies(lockfile)
          @lockfile_dependencies ||= {}
          @lockfile_dependencies[lockfile.name] ||=
            NpmAndYarn::FileParser.new(
              dependency_files: [lockfile, *package_files],
              source: nil,
              credentials: credentials
            ).parse
        end

        def handle_missing_package(package_name, error_message, yarn_lock)
          missing_dep = lockfile_dependencies(yarn_lock).
                        find { |dep| dep.name == package_name }

          raise_resolvability_error(error_message, yarn_lock) unless missing_dep

          reg = NpmAndYarn::UpdateChecker::RegistryFinder.new(
            dependency: missing_dep,
            credentials: credentials,
            npmrc_file: npmrc_file,
            yarnrc_file: yarnrc_file,
            yarnrc_yml_file: yarnrc_yml_file
          ).registry

          return if UpdateChecker::RegistryFinder.central_registry?(reg) && !package_name.start_with?("@")

          raise PrivateSourceAuthenticationFailure, reg
        end

        def raise_resolvability_error(error_message, yarn_lock)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error whilst updating #{dependency_names} in " \
                "#{yarn_lock.path}:\n#{error_message}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        def handle_timeout(error_message, yarn_lock)
          url = error_message.match(TIMEOUT_FETCHING_PACKAGE).
                named_captures["url"]
          raise if URI(url).host == "registry.npmjs.org"

          package_name = error_message.match(TIMEOUT_FETCHING_PACKAGE).
                         named_captures["package"]
          sanitized_name = sanitize_package_name(package_name)

          dep = lockfile_dependencies(yarn_lock).
                find { |d| d.name == sanitized_name }
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
              dependencies: top_level_dependencies
            ).updated_package_json.content
        end

        def npmrc_disables_lockfile?
          npmrc_content.match?(/^package-lock\s*=\s*false/)
        end

        def yarnrc_specifies_private_reg?
          return false unless yarnrc_file

          regex = UpdateChecker::RegistryFinder::YARN_GLOBAL_REGISTRY_REGEX
          yarnrc_global_registry =
            yarnrc_file.content.
            lines.find { |line| line.match?(regex) }&.
            match(regex)&.
            named_captures&.
            fetch("registry")

          return false unless yarnrc_global_registry

          UpdateChecker::RegistryFinder::CENTRAL_REGISTRIES.any? do |r|
            r.include?(URI(yarnrc_global_registry).host)
          end
        end

        def yarnrc_content
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).yarnrc_content
        end

        def sanitized_package_json_content(content)
          updated_content =
            content.
            gsub(/\{\{[^\}]*?\}\}/, "something"). # {{ nm }} syntax not allowed
            gsub(/(?<!\\)\\ /, " ").          # escaped whitespace not allowed
            gsub(%r{^\s*//.*}, " ")           # comments are not allowed

          json = JSON.parse(updated_content)
          json["name"] = json["name"].delete(" ") if json["name"].is_a?(String)
          json.to_json
        end

        def sanitize_package_name(package_name)
          package_name.gsub("%2f", "/").gsub("%2F", "/")
        end

        def yarn_locks
          @yarn_locks ||=
            dependency_files.
            select { |f| f.name.end_with?("yarn.lock") }
        end

        def package_files
          dependency_files.select { |f| f.name.end_with?("package.json") }
        end

        def yarnrc_file
          dependency_files.find { |f| f.name == ".yarnrc" }
        end

        def npmrc_file
          dependency_files.find { |f| f.name == ".npmrc" }
        end

        def yarnrc_yml_file
          dependency_files.find { |f| f.name.end_with?(".yarnrc.yml") }
        end

        def yarnrc_yml_content
          yarnrc_yml_file.content
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
