# frozen_string_literal: true

require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/shared_helpers"
require "dependabot/errors"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module NpmAndYarn
    class FileUpdater
      class NpmLockfileUpdater
        require_relative "npmrc_builder"
        require_relative "package_json_updater"

        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
        end

        def updated_lockfile_content(lockfile)
          return lockfile.content if npmrc_disables_lockfile?
          return lockfile.content if updatable_dependencies(lockfile).empty?

          @updated_lockfile_content ||= {}
          @updated_lockfile_content[lockfile.name] ||=
            SharedHelpers.in_a_temporary_directory do
              path = Pathname.new(lockfile.name).dirname.to_s
              lockfile_name = Pathname.new(lockfile.name).basename.to_s
              write_temporary_dependency_files(lockfile.name)
              updated_files = Dir.chdir(path) do
                run_current_npm_update(lockfile_name: lockfile_name)
              end
              updated_content = updated_files.fetch(lockfile_name)
              post_process_npm_lockfile(lockfile.content, updated_content)
            end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_npm_updater_error(e, lockfile)
        end

        private

        attr_reader :dependencies, :dependency_files, :credentials

        UNREACHABLE_GIT =
          /ls-remote (?:(-h -t)|(--tags --heads)) (?<url>.*)/.freeze
        FORBIDDEN_PACKAGE =
          %r{(?<package_req>[^/]+) - (Forbidden|Unauthorized)}.freeze
        FORBIDDEN_PACKAGE_403 = %r{^403\sForbidden\s
          -\sGET\shttps?://(?<source>[^/]+)/(?<package_req>[^/\s]+)}x.freeze
        MISSING_PACKAGE = %r{(?<package_req>[^/]+) - Not found}.freeze
        INVALID_PACKAGE = /Can't install (?<package_req>.*): Missing/.freeze

        def top_level_dependencies
          dependencies.select(&:top_level?)
        end

        def sub_dependencies
          dependencies.reject(&:top_level?)
        end

        def updatable_dependencies(lockfile)
          lockfile_dir = Pathname.new(lockfile.name).dirname.to_s
          dependencies.reject do |dependency|
            dependency_up_to_date?(lockfile, dependency) ||
              top_level_dependency_update_not_required?(dependency,
                                                        lockfile_dir)
          end
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

        def dependency_up_to_date?(lockfile, dependency)
          existing_dep = lockfile_dependencies(lockfile).
                         find { |dep| dep.name == dependency.name }

          # If the dependency is missing but top level it should be treated as
          # not up to date
          # If it's a missing sub dependency we treat it as up to date
          # (likely it is no longer required)
          return !dependency.top_level? if existing_dep.nil?

          existing_dep&.version == dependency.version
        end

        # Prevent changes to the lockfile when the dependency has been
        # required in a package.json outside the current folder (e.g. lerna
        # proj)
        def top_level_dependency_update_not_required?(dependency,
                                                      lockfile_dir)
          requirements_for_path = dependency.requirements.select do |req|
            req_dir = Pathname.new(req[:file]).dirname.to_s
            req_dir == lockfile_dir
          end

          dependency.top_level? && requirements_for_path.empty?
        end

        def run_current_npm_update(lockfile_name:)
          top_level_dependency_updates = top_level_dependencies.map do |d|
            { name: d.name, version: d.version, requirements: d.requirements }
          end

          run_npm_updater(
            lockfile_name: lockfile_name,
            top_level_dependency_updates: top_level_dependency_updates
          )
        end

        def run_previous_npm_update(lockfile_name:)
          previous_top_level_dependencies = top_level_dependencies.map do |d|
            {
              name: d.name,
              version: d.previous_version,
              requirements: d.previous_requirements
            }
          end

          run_npm_updater(
            lockfile_name: lockfile_name,
            top_level_dependency_updates: previous_top_level_dependencies
          )
        end

        def run_npm_updater(lockfile_name:, top_level_dependency_updates:)
          SharedHelpers.with_git_configured(credentials: credentials) do
            if top_level_dependency_updates.any?
              run_npm_top_level_updater(
                lockfile_name: lockfile_name,
                top_level_dependency_updates: top_level_dependency_updates
              )
            else
              run_npm_subdependency_updater(lockfile_name: lockfile_name)
            end
          end
        end

        def run_npm_top_level_updater(lockfile_name:,
                                      top_level_dependency_updates:)
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "npm:update",
            args: [
              Dir.pwd,
              lockfile_name,
              top_level_dependency_updates
            ]
          )
        end

        def run_npm_subdependency_updater(lockfile_name:)
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "npm:updateSubdependency",
            args: [Dir.pwd, lockfile_name, sub_dependencies.map(&:to_h)]
          )
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        def handle_npm_updater_error(error, lockfile)
          if error.message.match?(MISSING_PACKAGE)
            package_name =
              error.message.match(MISSING_PACKAGE).
              named_captures["package_req"].
              gsub("%2f", "/")
            handle_missing_package(package_name, error, lockfile)
          end

          # Invalid package: When the package.json doesn't include a name or
          # version, or name has non url-friendly characters
          # Local path error: When installing a git dependency which
          # is using local file paths for sub-dependencies (e.g. unbuilt yarn
          # workspace project)
          sub_dep_local_path_error = "does not contain a package.json file"
          if error.message.match?(INVALID_PACKAGE) ||
             error.message.start_with?("Invalid package name") ||
             error.message.include?(sub_dep_local_path_error)
            raise_resolvability_error(error, lockfile)
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
          if error.message.start_with?("No matching vers") &&
             dependencies_in_error_message?(error.message) &&
             resolvable_before_update?(lockfile)

            # Raise a bespoke error so we can capture and ignore it if
            # we're trying to create a new PR (which will be created
            # successfully at a later date)
            raise Dependabot::InconsistentRegistryResponse, error.message
          end

          if error.message.match?(FORBIDDEN_PACKAGE)
            package_name =
              error.message.match(FORBIDDEN_PACKAGE).
              named_captures["package_req"].
              gsub("%2f", "/")
            handle_missing_package(package_name, error, lockfile)
          end

          # Some private registries return a 403 when the user is readonly
          if error.message.match?(FORBIDDEN_PACKAGE_403)
            package_name =
              error.message.match(FORBIDDEN_PACKAGE_403).
              named_captures["package_req"].
              gsub("%2f", "/")
            handle_missing_package(package_name, error, lockfile)
          end

          if error.message.match?(UNREACHABLE_GIT)
            dependency_url =
              error.message.match(UNREACHABLE_GIT).
              named_captures.fetch("url")

            raise Dependabot::GitDependenciesNotReachable, dependency_url
          end

          # This error happens when the lockfile has been messed up and some
          # entries are missing a version, source:
          # https://npm.community/t/cannot-read-property-match-of-undefined/203/3
          #
          # In this case we want to raise a more helpful error message asking
          # people to re-generate their lockfiles (Future feature idea: add a
          # way to click-to-fix the lockfile from the issue)
          if error.message.include?("Cannot read property 'match' of ") &&
             !resolvable_before_update?(lockfile)
            raise_missing_lockfile_version_resolvability_error(error, lockfile)
          end

          if (error.message.start_with?("No matching vers", "404 Not Found") ||
             error.message.include?("not match any file(s) known to git") ||
             error.message.include?("Non-registry package missing package") ||
             error.message.include?("Invalid tag name")) &&
             !resolvable_before_update?(lockfile)
            raise_resolvability_error(error, lockfile)
          end

          raise error
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength

        def raise_resolvability_error(error, lockfile)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error whilst updating #{dependency_names} in "\
                "#{lockfile.path}:\n#{error.message}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        def raise_missing_lockfile_version_resolvability_error(error, lockfile)
          lockfile_dir = Pathname.new(lockfile.name).dirname
          modules_path = lockfile_dir.join("node_modules")
          # Note: don't include the dependency names to prevent opening
          # multiple issues for each dependency that fails because we unique
          # issues on the error message (issue detail) on the backend
          #
          # ToDo: add an error ID to issues to make it easier to unique them
          msg = "Error whilst updating dependencies in #{lockfile.name}:\n"\
                "#{error.message}\n\n"\
                "It looks like your lockfile has some corrupt entries with "\
                "missing versions and needs to be re-generated.\n"\
                "You'll need to remove #{lockfile.name} and #{modules_path} "\
                "before you run npm install."
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        def handle_missing_package(package_name, error, lockfile)
          missing_dep = lockfile_dependencies(lockfile).
                        find { |dep| dep.name == package_name }

          raise_resolvability_error(error, lockfile) unless missing_dep

          reg = NpmAndYarn::UpdateChecker::RegistryFinder.new(
            dependency: missing_dep,
            credentials: credentials,
            npmrc_file: dependency_files.
                        find { |f| f.name.end_with?(".npmrc") },
            yarnrc_file: dependency_files.
                         find { |f| f.name.end_with?(".yarnrc") }
          ).registry

          return if central_registry?(reg) && !package_name.start_with?("@")

          raise Dependabot::PrivateSourceAuthenticationFailure, reg
        end

        def central_registry?(registry)
          NpmAndYarn::FileParser::CENTRAL_REGISTRIES.any? do |r|
            r.include?(registry)
          end
        end

        def resolvable_before_update?(lockfile)
          @resolvable_before_update ||= {}
          if @resolvable_before_update.key?(lockfile.name)
            return @resolvable_before_update[lockfile.name]
          end

          @resolvable_before_update[lockfile.name] =
            begin
              SharedHelpers.in_a_temporary_directory do
                write_temporary_dependency_files(
                  lockfile.name,
                  update_package_json: false
                )

                lockfile_name = Pathname.new(lockfile.name).basename.to_s
                path = Pathname.new(lockfile.name).dirname.to_s
                Dir.chdir(path) do
                  run_previous_npm_update(lockfile_name: lockfile_name)
                end
              end

              true
            rescue SharedHelpers::HelperSubprocessFailed
              false
            end
        end

        def dependencies_in_error_message?(message)
          names = dependencies.map { |dep| dep.name.split("/").first }
          # Example foramt: No matching version found for
          # @dependabot/dummy-pkg-b@^1.3.0
          names.any? do |name|
            message.match?(%r{#{Regexp.quote(name)}[\/@]})
          end
        end

        def write_temporary_dependency_files(lockfile_name,
                                             update_package_json: true)
          write_lockfiles(lockfile_name)
          File.write(".npmrc", npmrc_content)

          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)

            updated_content =
              if update_package_json && top_level_dependencies.any?
                updated_package_json_content(file)
              else
                file.content
              end

            # When updating a package-lock.json we have to manually lock all
            # git dependencies, otherwise npm will (unhelpfully) update them
            updated_content = lock_git_deps(updated_content)
            updated_content = replace_ssh_sources(updated_content)

            updated_content = sanitized_package_json_content(updated_content)
            File.write(file.name, updated_content)
          end
        end

        def write_lockfiles(lockfile_name)
          excluded_lock =
            case lockfile_name
            when "package-lock.json" then "npm-shrinkwrap.json"
            when "npm-shrinkwrap.json" then "package-lock.json"
            end
          [*package_locks, *shrinkwraps].each do |f|
            next if f.name == excluded_lock

            FileUtils.mkdir_p(Pathname.new(f.name).dirname)

            File.write(f.name, f.content)
          end
        end

        def lock_git_deps(content)
          return content if git_dependencies_to_lock.empty?

          types = NpmAndYarn::FileParser::DEPENDENCY_TYPES

          json = JSON.parse(content)
          types.each do |type|
            json.fetch(type, {}).each do |nm, _|
              updated_version = git_dependencies_to_lock.dig(nm, :version)
              next unless updated_version

              json[type][nm] = git_dependencies_to_lock[nm][:version]
            end
          end

          json.to_json
        end

        def git_dependencies_to_lock
          return {} unless package_locks.any?
          return @git_dependencies_to_lock if @git_dependencies_to_lock

          @git_dependencies_to_lock = {}
          dependency_names = dependencies.map(&:name)

          package_locks.each do |package_lock|
            parsed_lockfile = JSON.parse(package_lock.content)
            parsed_lockfile.fetch("dependencies", {}).each do |nm, details|
              next if dependency_names.include?(nm)
              next unless details["version"]
              next unless details["version"].start_with?("git")

              @git_dependencies_to_lock[nm] = {
                version: details["version"],
                from: details["from"]
              }
            end
          end
          @git_dependencies_to_lock
        end

        def replace_ssh_sources(content)
          updated_content = content

          git_ssh_requirements_to_swap.each do |req|
            new_req = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'https://\1/')
            updated_content = updated_content.gsub(req, new_req)
          end

          updated_content
        end

        def git_ssh_requirements_to_swap
          return @git_ssh_requirements_to_swap if @git_ssh_requirements_to_swap

          @git_ssh_requirements_to_swap = []

          package_files.each do |file|
            NpmAndYarn::FileParser::DEPENDENCY_TYPES.each do |t|
              JSON.parse(file.content).fetch(t, {}).each do |_, requirement|
                next unless requirement.start_with?("git+ssh:")

                req = requirement.split("#").first
                @git_ssh_requirements_to_swap << req
              end
            end
          end

          @git_ssh_requirements_to_swap
        end

        def post_process_npm_lockfile(original_content, updated_content)
          updated_content =
            replace_project_metadata(updated_content, original_content)

          # Switch SSH requirements back for git dependencies
          git_ssh_requirements_to_swap.each do |req|
            new_r = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'git+https://\1/')
            old_r = req.gsub(%r{git@(.*?)[:/]}, 'git@\1/')
            updated_content = updated_content.gsub(new_r, old_r)
          end

          # Switch from details back for git dependencies (they will have
          # changed because we locked them)
          git_dependencies_to_lock.each do |_, details|
            next unless details[:version] && details[:from]

            # When locking git dependencies in package.json we set the version
            # to be the git commit from the lockfile "version" field which
            # updates the lockfile "from" field to the new git commit when we
            # run npm install
            locked_from = %("from": "#{details[:version]}")
            original_from = %("from": "#{details[:from]}")
            updated_content = updated_content.gsub(locked_from, original_from)
          end

          # Switch back the protocol of tarball resolutions if they've changed
          # (fixes an npm bug, which appears to be applied inconsistently)
          tarball_urls.each do |url|
            trimmed_url = url.gsub(/(\d+\.)*tgz$/, "")
            incorrect_url = if url.start_with?("https")
                              trimmed_url.gsub(/^https:/, "http:")
                            else trimmed_url.gsub(/^http:/, "https:")
                            end
            updated_content = updated_content.gsub(
              /#{Regexp.quote(incorrect_url)}(?=(\d+\.)*tgz")/,
              trimmed_url
            )
          end

          updated_content
        end

        def replace_project_metadata(new_content, old_content)
          old_name = old_content.match(/(?<="name": ").*(?=",)/)&.to_s

          if old_name
            new_content = new_content.
                          sub(/(?<="name": ").*(?=",)/, old_name)
          end

          new_content
        end

        def tarball_urls
          all_urls = [*package_locks, *shrinkwraps].flat_map do |file|
            file.content.scan(/"resolved":\s+"(.*)\"/).flatten
          end
          all_urls.uniq! { |url| url.gsub(/(\d+\.)*tgz$/, "") }

          # If both the http:// and https:// versions of the tarball appear
          # in the lockfile, prefer the https:// one
          trimmed_urls = all_urls.map { |url| url.gsub(/(\d+\.)*tgz$/, "") }
          all_urls.reject do |url|
            next false unless url.start_with?("http:")

            trimmed_url = url.gsub(/(\d+\.)*tgz$/, "")
            trimmed_urls.include?(trimmed_url.gsub(/^http:/, "https:"))
          end
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

        def sanitized_package_json_content(content)
          content.
            gsub(/\{\{.*?\}\}/, "something"). # {{ name }} syntax not allowed
            gsub(/(?<!\\)\\ /, " ").          # escaped whitespace not allowed
            gsub(%r{^\s*//.*}, " ")           # comments are not allowed
        end

        def package_locks
          @package_locks ||=
            dependency_files.
            select { |f| f.name.end_with?("package-lock.json") }
        end

        def shrinkwraps
          @shrinkwraps ||=
            dependency_files.
            select { |f| f.name.end_with?("npm-shrinkwrap.json") }
        end

        def package_files
          dependency_files.select { |f| f.name.end_with?("package.json") }
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
