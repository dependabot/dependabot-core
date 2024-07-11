# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/logger"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/shared_helpers"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class NpmLockfileUpdater
        extend T::Sig

        require_relative "npmrc_builder"
        require_relative "package_json_updater"

        sig do
          params(
            lockfile: Dependabot::DependencyFile,
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Credential]
          )
            .void
        end
        def initialize(lockfile:, dependencies:, dependency_files:, credentials:)
          @lockfile = lockfile
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { returns(Dependabot::DependencyFile) }
        def updated_lockfile
          updated_file = lockfile.dup
          updated_file.content = updated_lockfile_content
          updated_file
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :lockfile

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Credential]) }
        attr_reader :credentials

        UNREACHABLE_GIT = /fatal: repository '(?<url>.*)' not found/
        FORBIDDEN_GIT = /fatal: Authentication failed for '(?<url>.*)'/
        FORBIDDEN_PACKAGE = %r{(?<package_req>[^/]+) - (Forbidden|Unauthorized)}
        FORBIDDEN_PACKAGE_403 = %r{^403\sForbidden\s
          -\sGET\shttps?://(?<source>[^/]+)/(?<package_req>[^/\s]+)}x
        MISSING_PACKAGE = %r{(?<package_req>[^/]+) - Not found}
        INVALID_PACKAGE = /Can't install (?<package_req>.*): Missing/
        SOCKET_HANG_UP = /request to (?<url>.*) failed, reason: socket hang up/

        # TODO: look into fixing this in npm, seems like a bug in the git
        # downloader introduced in npm 7
        #
        # NOTE: error message returned from arborist/npm 8 when trying to
        # fetching a invalid/non-existent git ref
        NPM8_MISSING_GIT_REF = /already exists and is not an empty directory/
        NPM6_MISSING_GIT_REF = /did not match any file\(s\) known to git/

        sig { returns(T.nilable(String)) }
        def updated_lockfile_content
          return lockfile.content if npmrc_disables_lockfile?
          return lockfile.content unless updatable_dependencies.any?

          @updated_lockfile_content ||= T.let(
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files
              updated_files = Dir.chdir(lockfile_directory) { run_current_npm_update }
              updated_lockfile_content = updated_files.fetch(lockfile_basename)
              post_process_npm_lockfile(updated_lockfile_content)
            end,
            T.nilable(String)
          )
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_npm_updater_error(e)
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def top_level_dependencies
          dependencies.select(&:top_level?)
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def sub_dependencies
          dependencies.reject(&:top_level?)
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def updatable_dependencies
          dependencies.reject do |dependency|
            dependency_up_to_date?(dependency) || top_level_dependency_update_not_required?(dependency)
          end
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def lockfile_dependencies
          @lockfile_dependencies ||= T.let(
            NpmAndYarn::FileParser.new(
              dependency_files: [lockfile, *package_files],
              source: nil,
              credentials: credentials
            ).parse,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def dependency_up_to_date?(dependency)
          existing_dep = lockfile_dependencies.find { |dep| dep.name == dependency.name }

          # If the dependency is missing but top level it should be treated as
          # not up to date
          # If it's a missing sub dependency we treat it as up to date
          # (likely it is no longer required)
          return !dependency.top_level? if existing_dep.nil?

          existing_dep.version == dependency.version
        end

        # NOTE: Prevent changes to npm 6 lockfiles when the dependency has been
        # required in a package.json outside the current folder (e.g. lerna
        # proj). npm 7 introduces workspace support so we explicitly want to
        # update the root lockfile and check if the dependency is in the
        # lockfile
        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def top_level_dependency_update_not_required?(dependency)
          dependency.top_level? &&
            !dependency_in_package_json?(dependency) &&
            !dependency_in_lockfile?(dependency)
        end

        sig { returns(T::Hash[String, String]) }
        def run_current_npm_update
          run_npm_updater(top_level_dependencies: top_level_dependencies, sub_dependencies: sub_dependencies)
        end

        sig { returns(T::Hash[String, String]) }
        def run_previous_npm_update
          previous_top_level_dependencies = top_level_dependencies.map do |d|
            Dependabot::Dependency.new(
              name: d.name,
              package_manager: d.package_manager,
              version: d.previous_version,
              previous_version: d.previous_version,
              requirements: T.must(d.previous_requirements),
              previous_requirements: d.previous_requirements
            )
          end

          previous_sub_dependencies = sub_dependencies.map do |d|
            Dependabot::Dependency.new(
              name: d.name,
              package_manager: d.package_manager,
              version: d.previous_version,
              previous_version: d.previous_version,
              requirements: [],
              previous_requirements: []
            )
          end

          run_npm_updater(top_level_dependencies: previous_top_level_dependencies,
                          sub_dependencies: previous_sub_dependencies)
        end

        sig do
          params(
            top_level_dependencies: T::Array[Dependabot::Dependency],
            sub_dependencies: T::Array[Dependabot::Dependency]
          )
            .returns(T::Hash[String, String])
        end
        def run_npm_updater(top_level_dependencies:, sub_dependencies:)
          SharedHelpers.with_git_configured(credentials: credentials) do
            updated_files = T.let({}, T::Hash[String, String])
            if top_level_dependencies.any?
              updated_files.merge!(run_npm_top_level_updater(top_level_dependencies: top_level_dependencies))
            end
            if sub_dependencies.any?
              updated_files.merge!(T.must(run_npm_subdependency_updater(sub_dependencies: sub_dependencies)))
            end
            updated_files
          end
        end

        sig { params(top_level_dependencies: T::Array[Dependabot::Dependency]).returns(T::Hash[String, String]) }
        def run_npm_top_level_updater(top_level_dependencies:)
          if npm8?
            run_npm8_top_level_updater(top_level_dependencies: top_level_dependencies)
          else
            T.cast(
              SharedHelpers.run_helper_subprocess(
                command: NativeHelpers.helper_path,
                function: "npm6:update",
                args: [
                  Dir.pwd,
                  lockfile_basename,
                  top_level_dependencies.map(&:to_h)
                ]
              ),
              T::Hash[String, String]
            )
          end
        end

        sig { params(top_level_dependencies: T::Array[Dependabot::Dependency]).returns(T::Hash[String, String]) }
        def run_npm8_top_level_updater(top_level_dependencies:)
          dependencies_in_current_package_json = top_level_dependencies.any? do |dependency|
            dependency_in_package_json?(dependency)
          end

          unless dependencies_in_current_package_json
            # NOTE: When updating a dependency in a nested workspace project, npm
            # will add the dependency as a new top-level dependency to the root
            # lockfile. To overcome this, we save the content before the update,
            # and then re-run `npm install` after the update against the previous
            # content to remove that
            previous_package_json = File.read(T.must(package_json).name)
          end

          # TODO: Update the npm 6 updater to use these args as we currently
          # do the same in the js updater helper, we've kept it separate for
          # the npm 7 rollout
          install_args = top_level_dependencies.map { |dependency| npm_install_args(dependency) }

          run_npm_install_lockfile_only(install_args)

          unless dependencies_in_current_package_json
            File.write(T.must(package_json).name, previous_package_json)

            run_npm_install_lockfile_only
          end

          { lockfile_basename => File.read(lockfile_basename) }
        end

        sig do
          params(sub_dependencies: T::Array[Dependabot::Dependency]).returns(T.nilable(T::Hash[String, String]))
        end
        def run_npm_subdependency_updater(sub_dependencies:)
          if npm8?
            run_npm8_subdependency_updater(sub_dependencies: sub_dependencies)
          else
            T.cast(
              SharedHelpers.run_helper_subprocess(
                command: NativeHelpers.helper_path,
                function: "npm6:updateSubdependency",
                args: [Dir.pwd, lockfile_basename, sub_dependencies.map(&:to_h)]
              ),
              T.nilable(T::Hash[String, String])
            )
          end
        end

        sig { params(sub_dependencies: T::Array[Dependabot::Dependency]).returns(T::Hash[String, String]) }
        def run_npm8_subdependency_updater(sub_dependencies:)
          dependency_names = sub_dependencies.map(&:name)
          NativeHelpers.run_npm8_subdependency_update_command(dependency_names)
          { lockfile_basename => File.read(lockfile_basename) }
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
        def updated_version_requirement_for_dependency(dependency)
          flattenend_manifest_dependencies[dependency.name]
        end

        # TODO: Add the raw updated requirement to the Dependency instance
        # instead of fishing it out of the updated package json, we need to do
        # this because we don't store the same requirement in
        # Dependency#requirements for git dependencies - see PackageJsonUpdater
        sig { returns(T::Hash[String, String]) }
        def flattenend_manifest_dependencies
          @flattenend_manifest_dependencies ||= T.let(
            NpmAndYarn::FileParser::DEPENDENCY_TYPES.inject({}) do |deps, type|
              deps.merge(parsed_package_json[type] || {})
            end,
            T.nilable(T::Hash[String, String])
          )
        end

        # Runs `npm install` with `--package-lock-only` flag to update the
        # lockfiile.
        #
        # Other npm flags:
        # - `--force` ignores checks for platform (os, cpu) and engines
        # - `--dry-run=false` the updater sets a global .npmrc with `dry-run: true`
        #   to work around an issue in npm 6, we don't want that here
        # - `--ignore-scripts` disables prepare and prepack scripts which are
        #   run when installing git dependencies
        sig { params(install_args: T::Array[String]).returns(String) }
        def run_npm_install_lockfile_only(install_args = [])
          command = [
            "install",
            *install_args,
            "--force",
            "--dry-run",
            "false",
            "--ignore-scripts",
            "--package-lock-only"
          ].join(" ")

          fingerprint = [
            "install",
            install_args.empty? ? "" : "<install_args>",
            "--force",
            "--dry-run",
            "false",
            "--ignore-scripts",
            "--package-lock-only"
          ].join(" ")

          Helpers.run_npm_command(command, fingerprint: fingerprint)
        end

        sig { params(dependency: Dependabot::Dependency).returns(String) }
        def npm_install_args(dependency)
          git_requirement = dependency.requirements.find { |req| req[:source] && req[:source][:type] == "git" }

          if git_requirement
            # NOTE: For git dependencies we loose some information about the
            # requirement that's only available in the package.json, e.g. when
            # specifying a semver tag:
            # `dependabot/depeendabot-core#semver:^0.1` - this is required to
            # pass the correct install argument to `npm install`
            updated_version_requirement = updated_version_requirement_for_dependency(dependency)
            updated_version_requirement ||= git_requirement[:source][:url]

            # NOTE: Git is configured to auth over https while updating
            updated_version_requirement = updated_version_requirement.gsub(
              %r{git\+ssh://git@(.*?)[:/]}, 'https://\1/'
            )

            # NOTE: Keep any semver range that has already been updated by the
            # PackageJsonUpdater when installing the new version
            if updated_version_requirement.include?(dependency.version)
              "#{dependency.name}@#{updated_version_requirement}"
            else
              "#{dependency.name}@#{updated_version_requirement.sub(/#.*/, '')}##{dependency.version}"
            end
          else
            "#{dependency.name}@#{dependency.version}"
          end
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def dependency_in_package_json?(dependency)
          dependency.requirements.any? do |req|
            req[:file] == T.must(package_json).name
          end
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def dependency_in_lockfile?(dependency)
          lockfile_dependencies.any? do |dep|
            dep.name == dependency.name
          end
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        sig { params(error: Exception).returns(T.noreturn) }
        def handle_npm_updater_error(error)
          error_message = error.message
          if error_message.match?(MISSING_PACKAGE)
            package_name = T.must(error_message.match(MISSING_PACKAGE))
                            .named_captures["package_req"]
            sanitized_name = sanitize_package_name(T.must(package_name))
            sanitized_error = error_message.gsub(T.must(package_name), sanitized_name)
            handle_missing_package(sanitized_name, sanitized_error)
          end

          # Invalid package: When the package.json doesn't include a name or
          # version, or name has non url-friendly characters
          # Local path error: When installing a git dependency which
          # is using local file paths for sub-dependencies (e.g. unbuilt yarn
          # workspace project)
          sub_dep_local_path_error = "does not contain a package.json file"
          if error_message.match?(INVALID_PACKAGE) ||
             error_message.include?("Invalid package name") ||
             error_message.include?(sub_dep_local_path_error)
            raise_resolvability_error(error_message)
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
          if error_message.include?("No matching vers") &&
             dependencies_in_error_message?(error_message) &&
             resolvable_before_update?

            # Raise a bespoke error so we can capture and ignore it if
            # we're trying to create a new PR (which will be created
            # successfully at a later date)
            raise Dependabot::InconsistentRegistryResponse, error_message
          end

          if error_message.match?(FORBIDDEN_PACKAGE)
            package_name = T.must(error_message.match(FORBIDDEN_PACKAGE))
                            .named_captures["package_req"]
            sanitized_name = sanitize_package_name(T.must(package_name))
            sanitized_error = error_message.gsub(T.must(package_name), sanitized_name)
            handle_missing_package(sanitized_name, sanitized_error)
          end

          # Some private registries return a 403 when the user is readonly
          if error_message.match?(FORBIDDEN_PACKAGE_403)
            package_name = T.must(error_message.match(FORBIDDEN_PACKAGE_403))
                            .named_captures["package_req"]
            sanitized_name = sanitize_package_name(T.must(package_name))
            sanitized_error = error_message.gsub(T.must(package_name), sanitized_name)
            handle_missing_package(sanitized_name, sanitized_error)
          end

          if (git_error = error_message.match(UNREACHABLE_GIT) || error_message.match(FORBIDDEN_GIT))
            dependency_url = git_error.named_captures.fetch("url")

            raise Dependabot::GitDependenciesNotReachable, T.must(dependency_url)
          end

          # This error happens when the lockfile has been messed up and some
          # entries are missing a version, source:
          # https://npm.community/t/cannot-read-property-match-of-undefined/203/3
          #
          # In this case we want to raise a more helpful error message asking
          # people to re-generate their lockfiles (Future feature idea: add a
          # way to click-to-fix the lockfile from the issue)
          if error_message.include?("Cannot read properties of undefined (reading 'match')") &&
             !resolvable_before_update?
            raise_missing_lockfile_version_resolvability_error(error_message)
          end

          if (error_message.include?("No matching vers") ||
             error_message.include?("404 Not Found") ||
             error_message.include?("Non-registry package missing package") ||
             error_message.include?("Invalid tag name") ||
             error_message.match?(NPM6_MISSING_GIT_REF) ||
             error_message.match?(NPM8_MISSING_GIT_REF)) &&
             !resolvable_before_update?
            raise_resolvability_error(error_message)
          end

          # NOTE: This check was introduced in npm8/arborist
          if error_message.include?("must provide string spec")
            msg = "Error parsing your package.json manifest: the version requirement must be a string"
            raise Dependabot::DependencyFileNotParseable, msg
          end

          if error_message.include?("EBADENGINE")
            msg = "Dependabot uses Node.js #{`node --version`.strip} and NPM #{`npm --version`.strip}. " \
                  "Due to the engine-strict setting, the update will not succeed."
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if (git_source = error_message.match(SOCKET_HANG_UP))
            msg = git_source.named_captures.fetch("url")
            raise Dependabot::PrivateSourceTimedOut, msg
          end

          raise error
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength

        sig { params(error_message: String).returns(T.noreturn) }
        def raise_resolvability_error(error_message)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error whilst updating #{dependency_names} in " \
                "#{lockfile.path}:\n#{error_message}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        sig { params(error_message: String).returns(T.noreturn) }
        def raise_missing_lockfile_version_resolvability_error(error_message)
          modules_path = File.join(lockfile_directory, "node_modules")
          # NOTE: don't include the dependency names to prevent opening
          # multiple issues for each dependency that fails because we unique
          # issues on the error message (issue detail) on the backend
          #
          # ToDo: add an error ID to issues to make it easier to unique them
          msg = "Error whilst updating dependencies in #{lockfile.name}:\n" \
                "#{error_message}\n\n" \
                "It looks like your lockfile has some corrupt entries with " \
                "missing versions and needs to be re-generated.\n" \
                "You'll need to remove #{lockfile.name} and #{modules_path} " \
                "before you run npm install."
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        sig { params(package_name: String, error_message: String).void }
        def handle_missing_package(package_name, error_message)
          missing_dep = lockfile_dependencies.find { |dep| dep.name == package_name }

          raise_resolvability_error(error_message) unless missing_dep

          reg = NpmAndYarn::UpdateChecker::RegistryFinder.new(
            dependency: missing_dep,
            credentials: credentials,
            npmrc_file: dependency_files. find { |f| f.name.end_with?(".npmrc") },
            yarnrc_file: dependency_files. find { |f| f.name.end_with?(".yarnrc") },
            yarnrc_yml_file: dependency_files.find { |f| f.name.end_with?(".yarnrc.yml") }
          ).registry

          return if UpdateChecker::RegistryFinder.central_registry?(reg) && !package_name.start_with?("@")

          raise Dependabot::PrivateSourceAuthenticationFailure, reg
        end

        sig { returns(T::Boolean) }
        def resolvable_before_update?
          @resolvable_before_update ||= T.let(
            begin
              SharedHelpers.in_a_temporary_directory do
                write_temporary_dependency_files(update_package_json: false)
                Dir.chdir(lockfile_directory) { run_previous_npm_update }
              end

              true
            rescue SharedHelpers::HelperSubprocessFailed
              false
            end,
            T.nilable(T::Boolean)
          )
        end

        sig { params(error_message: String).returns(T::Boolean) }
        def dependencies_in_error_message?(error_message)
          names = dependencies.map { |dep| dep.name.split("/").first }
          # Example format: No matching version found for
          # @dependabot/dummy-pkg-b@^1.3.0
          names.any? do |name|
            error_message.match?(%r{#{Regexp.quote(T.must(name))}[\/@]})
          end
        end

        sig { params(update_package_json: T::Boolean).void }
        def write_temporary_dependency_files(update_package_json: true)
          write_lockfiles

          File.write(File.join(lockfile_directory, ".npmrc"), npmrc_content)

          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)

            updated_content = T.must(
              if update_package_json && top_level_dependencies.any?
                updated_package_json_content(file)
              else
                file.content
              end
            )

            package_json_preparer = package_json_preparer(updated_content)

            # TODO: Figure out if we need to lock git deps for npm 7 and can
            # start deprecating this hornets nest
            #
            # NOTE: When updating a package-lock.json we have to manually lock
            # all git dependencies, otherwise npm will (unhelpfully) update them
            updated_content = lock_git_deps(updated_content)
            updated_content = package_json_preparer.replace_ssh_sources(updated_content)
            updated_content = lock_deps_with_latest_reqs(updated_content)

            updated_content = package_json_preparer.remove_invalid_characters(updated_content)

            File.write(file.name, updated_content)
          end
        end

        sig { void }
        def write_lockfiles
          excluded_lock =
            case lockfile.name
            when "package-lock.json" then "npm-shrinkwrap.json"
            when "npm-shrinkwrap.json" then "package-lock.json"
            end
          [*package_locks, *shrinkwraps].each do |f|
            next if f.name == excluded_lock

            FileUtils.mkdir_p(Pathname.new(f.name).dirname)

            File.write(f.name, f.content)
          end
        end

        # Takes a JSON string and detects if it is spaces or tabs and how many
        # levels deep it is indented.
        sig { params(json: String).returns(String) }
        def detect_indentation(json)
          indentation = T.cast(json.scan(/^[[:blank:]]+/).min_by(&:length), T.nilable(String))
          return "" if indentation.nil? # let npm set the default if we can't detect any indentation

          indentation_size = indentation.length
          indentation_type = indentation.scan("\t").any? ? "\t" : " "

          indentation_type * indentation_size
        end

        sig { params(content: String).returns(String) }
        def lock_git_deps(content)
          return content if git_dependencies_to_lock.empty?

          json = JSON.parse(content)
          NpmAndYarn::FileParser.each_dependency(json) do |nm, _, type|
            updated_version = git_dependencies_to_lock.dig(nm, :version)
            next unless updated_version

            json[type][nm] = git_dependencies_to_lock[nm][:version]
          end

          indent = detect_indentation(content)
          JSON.pretty_generate(json, indent: indent)
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def git_dependencies_to_lock
          return {} unless package_locks.any?
          return @git_dependencies_to_lock if @git_dependencies_to_lock

          @git_dependencies_to_lock = T.let({}, T.nilable(T::Hash[String, T.untyped]))
          dependency_names = dependencies.map(&:name)

          package_locks.each do |package_lock|
            parsed_lockfile = JSON.parse(T.must(package_lock.content))
            parsed_lockfile.fetch("dependencies", {}).each do |nm, details|
              next if dependency_names.include?(nm)
              next unless details["version"]
              next unless details["version"].start_with?("git")

              T.must(@git_dependencies_to_lock)[nm] = {
                version: details["version"],
                from: details["from"]
              }
            end
          end
          T.must(@git_dependencies_to_lock)
        end

        # When a package.json version requirement is set to `latest`, npm will
        # always try to update these dependencies when doing an `npm install`,
        # regardless of lockfile version. Prevent any unrelated updates by
        # changing the version requirement to `*` while updating the lockfile.
        sig { params(content: String).returns(String) }
        def lock_deps_with_latest_reqs(content)
          json = JSON.parse(content)

          NpmAndYarn::FileParser.each_dependency(json) do |nm, requirement, type|
            next unless requirement == "latest"

            json[type][nm] = "*"
          end

          indent = detect_indentation(content)
          JSON.pretty_generate(json, indent: indent)
        end

        sig { returns(T::Array[String]) }
        def git_ssh_requirements_to_swap
          @git_ssh_requirements_to_swap ||= T.let(
            package_files.flat_map do |file|
              package_json_preparer(T.must(file.content)).swapped_ssh_requirements
            end,
            T.nilable(T::Array[String])
          )
        end

        sig { params(updated_lockfile_content: String).returns(String) }
        def post_process_npm_lockfile(updated_lockfile_content)
          # Switch SSH requirements back for git dependencies
          updated_lockfile_content = replace_swapped_git_ssh_requirements(updated_lockfile_content)

          # Switch from details back for git dependencies (they will have
          # changed because we locked them)
          updated_lockfile_content = replace_locked_git_dependencies(updated_lockfile_content)

          parsed_updated_lockfile_content = JSON.parse(updated_lockfile_content)

          # Restore lockfile name attribute from the original lockfile
          updated_lockfile_content = replace_project_name(updated_lockfile_content, parsed_updated_lockfile_content)

          # Restore npm 8 "packages" "name" entry from package.json if previously set
          updated_lockfile_content = restore_packages_name(updated_lockfile_content, parsed_updated_lockfile_content)

          # Switch back npm 8 lockfile "packages" requirements from the package.json
          updated_lockfile_content = restore_locked_package_dependencies(
            updated_lockfile_content, parsed_updated_lockfile_content
          )

          # Switch back the protocol of tarball resolutions if they've changed
          # (fixes an npm bug, which appears to be applied inconsistently)
          replace_tarball_urls(updated_lockfile_content)
        end

        sig do
          params(
            updated_lockfile_content: String,
            parsed_updated_lockfile_content: T::Hash[String, T.untyped]
          )
            .returns(String)
        end
        def replace_project_name(updated_lockfile_content, parsed_updated_lockfile_content)
          current_name = parsed_updated_lockfile_content["name"]
          original_name = parsed_lockfile["name"]
          if original_name
            updated_lockfile_content = replace_lockfile_name_attribute(
              current_name, original_name, updated_lockfile_content
            )
          end
          updated_lockfile_content
        end

        sig do
          params(
            updated_lockfile_content: String,
            parsed_updated_lockfile_content: T::Hash[String, T.untyped]
          )
            .returns(String)
        end
        def restore_packages_name(updated_lockfile_content, parsed_updated_lockfile_content)
          return updated_lockfile_content unless npm8?

          current_name = parsed_updated_lockfile_content.dig("packages", "", "name")
          original_name = parsed_lockfile.dig("packages", "", "name")

          # TODO: Submit a patch to npm fixing this issue making `npm install`
          # consistent with `npm install --package-lock-only`
          #
          # NOTE: This is a workaround for npm adding a `name` attribute to the
          # packages section in the lockfile because we install using
          # `--package-lock-only`
          if !original_name
            updated_lockfile_content = remove_lockfile_packages_name_attribute(
              current_name, updated_lockfile_content
            )
          elsif original_name && original_name != current_name
            updated_lockfile_content = replace_lockfile_packages_name_attribute(
              current_name, original_name, updated_lockfile_content
            )
          end

          updated_lockfile_content
        end

        sig do
          params(
            current_name: String,
            original_name: String,
            updated_lockfile_content: String
          )
            .returns(String)
        end
        def replace_lockfile_name_attribute(current_name, original_name, updated_lockfile_content)
          updated_lockfile_content.sub(
            /"name":\s"#{current_name}"/,
            "\"name\": \"#{original_name}\""
          )
        end

        sig do
          params(
            current_name: String,
            original_name: String,
            updated_lockfile_content: String
          )
            .returns(String)
        end
        def replace_lockfile_packages_name_attribute(current_name, original_name, updated_lockfile_content)
          packages_key_line = '"": {'
          updated_lockfile_content.sub(
            /(#{packages_key_line}[\n\s]+"name":\s)"#{current_name}"/,
            '\1"' + original_name + '"'
          )
        end

        sig { params(current_name: String, updated_lockfile_content: String).returns(String) }
        def remove_lockfile_packages_name_attribute(current_name, updated_lockfile_content)
          packages_key_line = '"": {'
          updated_lockfile_content.gsub(/(#{packages_key_line})[\n\s]+"name":\s"#{current_name}",/, '\1')
        end

        # NOTE: This is a workaround to "sync" what's in package.json
        # requirements and the `packages.""` entry in npm 8 v2 lockfiles. These
        # get out of sync because we lock git dependencies (that are not being
        # updated) to a specific sha to prevent unrelated updates and the way we
        # invoke the `npm install` cli, where we might tell npm to install a
        # specific version e.g. `npm install eslint@1.1.8` but we keep the
        # `package.json` requirement for eslint at `^1.0.0`, in which case we
        # need to copy this from the manifest to the lockfile after the update
        # has finished.
        sig do
          params(
            updated_lockfile_content: String,
            parsed_updated_lockfile_content: T::Hash[String, T.untyped]
          )
            .returns(String)
        end
        def restore_locked_package_dependencies(updated_lockfile_content, parsed_updated_lockfile_content)
          return updated_lockfile_content unless npm8?

          dependency_names_to_restore = (dependencies.map(&:name) + git_dependencies_to_lock.keys).uniq

          NpmAndYarn::FileParser.each_dependency(parsed_package_json) do |dependency_name, original_requirement, type|
            next unless dependency_names_to_restore.include?(dependency_name)

            locked_requirement = parsed_updated_lockfile_content.dig("packages", "", type, dependency_name)
            next unless locked_requirement

            locked_req = %("#{dependency_name}": "#{locked_requirement}")
            original_req = %("#{dependency_name}": "#{original_requirement}")
            updated_lockfile_content = updated_lockfile_content.gsub(locked_req, original_req)
          end

          updated_lockfile_content
        end

        sig { params(updated_lockfile_content: String).returns(String) }
        def replace_swapped_git_ssh_requirements(updated_lockfile_content)
          git_ssh_requirements_to_swap.each do |req|
            new_r = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'git+https://\1/')
            old_r = req.gsub(%r{git@(.*?)[:/]}, 'git@\1/')
            updated_lockfile_content = updated_lockfile_content.gsub(new_r, old_r)
          end

          updated_lockfile_content
        end

        sig { params(updated_lockfile_content: String).returns(String) }
        def replace_locked_git_dependencies(updated_lockfile_content)
          # Switch from details back for git dependencies (they will have
          # changed because we locked them)
          git_dependencies_to_lock.each do |dependency_name, details|
            next unless details[:version] && details[:from]

            # When locking git dependencies in package.json we set the version
            # to be the git commit from the lockfile "version" field which
            # updates the lockfile "from" field to the new git commit when we
            # run npm install
            original_from = %("from": "#{details[:from]}")
            if npm8?
              # NOTE: The `from` syntax has changed in npm 7 to include the dependency name
              npm8_locked_from = %("from": "#{dependency_name}@#{details[:version]}")
              updated_lockfile_content = updated_lockfile_content.gsub(npm8_locked_from, original_from)
            else
              npm6_locked_from = %("from": "#{details[:version]}")
              updated_lockfile_content = updated_lockfile_content.gsub(npm6_locked_from, original_from)
            end
          end

          updated_lockfile_content
        end

        sig { params(updated_lockfile_content: String).returns(String) }
        def replace_tarball_urls(updated_lockfile_content)
          tarball_urls.each do |url|
            trimmed_url = url.gsub(/(\d+\.)*tgz$/, "")
            incorrect_url = if url.start_with?("https")
                              trimmed_url.gsub(/^https:/, "http:")
                            else
                              trimmed_url.gsub(/^http:/, "https:")
                            end
            updated_lockfile_content = updated_lockfile_content.gsub(
              /#{Regexp.quote(incorrect_url)}(?=(\d+\.)*tgz")/,
              trimmed_url
            )
          end

          updated_lockfile_content
        end

        sig { returns(T::Array[String]) }
        def tarball_urls
          all_urls = [*package_locks, *shrinkwraps].flat_map do |file|
            T.must(file.content).scan(/"resolved":\s+"(.*)\"/).flatten
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

        sig { returns(String) }
        def npmrc_content
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content
        end

        sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def updated_package_json_content(file)
          @updated_package_json_content ||= T.let(
            {},
            T.nilable(T::Hash[String, T.nilable(String)])
          )
          @updated_package_json_content[file.name] ||= T.let(
            PackageJsonUpdater.new(
              package_json: file,
              dependencies: top_level_dependencies
            ).updated_package_json.content,
            T.nilable(String)
          )
        end

        sig { params(content: String).returns(Dependabot::NpmAndYarn::FileUpdater::PackageJsonPreparer) }
        def package_json_preparer(content)
          @package_json_preparer ||= T.let(
            {},
            T.nilable(T::Hash[String, Dependabot::NpmAndYarn::FileUpdater::PackageJsonPreparer])
          )
          @package_json_preparer[content] ||=
            PackageJsonPreparer.new(
              package_json_content: content
            )
        end

        sig { returns(T::Boolean) }
        def npmrc_disables_lockfile?
          npmrc_content.match?(/^package-lock\s*=\s*false/)
        end

        sig { returns(T::Boolean) }
        def npm8?
          return T.must(@npm8) if defined?(@npm8)

          @npm8 ||= T.let(
            Dependabot::NpmAndYarn::Helpers.npm8?(lockfile),
            T.nilable(T::Boolean)
          )
        end

        sig { params(package_name: String).returns(String) }
        def sanitize_package_name(package_name)
          package_name.gsub("%2f", "/").gsub("%2F", "/")
        end

        sig { returns(String) }
        def lockfile_directory
          Pathname.new(lockfile.name).dirname.to_s
        end

        sig { returns(String) }
        def lockfile_basename
          Pathname.new(lockfile.name).basename.to_s
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_lockfile
          @parsed_lockfile ||= T.let(
            JSON.parse(T.must(lockfile.content)),
            T.nilable(T::Hash[String, T.untyped])
          )
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_package_json
          return {} unless package_json

          @parsed_package_json ||= T.let(
            JSON.parse(T.must(updated_package_json_content(T.must(package_json)))),
            T.nilable(T::Hash[String, T.untyped])
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def package_json
          package_name = lockfile.name.sub(lockfile_basename, "package.json")
          package_files.find { |f| f.name == package_name }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_locks
          @package_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("package-lock.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def shrinkwraps
          @shrinkwraps ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("npm-shrinkwrap.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_files
          dependency_files.select { |f| f.name.end_with?("package.json") }
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
