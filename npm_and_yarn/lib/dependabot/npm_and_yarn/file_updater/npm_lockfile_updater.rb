# frozen_string_literal: true

require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
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
              updated_content = post_process_npm_lockfile(updated_content)
              raise "No change!" if lockfile.content == updated_content

              updated_content
            end
        rescue SharedHelpers::HelperSubprocessFailed => error
          handle_npm_updater_error(error, lockfile)
        end

        private

        attr_reader :dependencies, :dependency_files, :credentials

        UNREACHABLE_GIT =
          /ls-remote (?:(-h -t)|(--tags --heads)) (?<url>.*)/.freeze
        FORBIDDEN_PACKAGE =
          /(403 Forbidden|401 Unauthorized): (?<package_req>.*)/.freeze
        MISSING_PACKAGE = /404 Not Found: (?<package_req>.*)/.freeze
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

        def dependency_up_to_date?(lockfile, dependency)
          existing_dep = NpmAndYarn::FileParser.new(
            dependency_files: [lockfile, *package_files],
            source: nil,
            credentials: credentials
          ).parse.find { |dep| dep.name == dependency.name }

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
            command: "node #{npm_helper_path}",
            function: "update",
            args: [
              Dir.pwd,
              top_level_dependency_updates,
              lockfile_name
            ]
          )
        end

        def run_npm_subdependency_updater(lockfile_name:)
          SharedHelpers.run_helper_subprocess(
            command: "node #{npm_helper_path}",
            function: "updateSubdependency",
            args: [Dir.pwd, lockfile_name]
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
              split(/(?<=\w)\@/).first
            handle_missing_package(package_name, error, lockfile)
          end
          names = dependencies.map(&:name)
          if names.any? { |name| error.message.include?("#{name}@") } &&
             error.message.start_with?("No matching vers") &&
             resolvable_before_update?(lockfile)
            # This happens if a new version has been published that relies on
            # but npm is having consistency issues. We raise a bespoke error
            # so we can capture and ignore it if we're trying to create a new
            # PR (which will be created successfully at a later date).
            raise Dependabot::InconsistentRegistryResponse, error.message
          end

          # When the package.json doesn't include a name or version, or name
          # has non url-friendly characters
          if error.message.match?(INVALID_PACKAGE) ||
             error.message.start_with?("Invalid package name")
            raise_resolvability_error(error, lockfile)
          end

          if error.message.start_with?("No matching vers", "404 Not Found") ||
             error.message.include?("not match any file(s) known to git") ||
             error.message.include?("Non-registry package missing package") ||
             error.message.include?("Cannot read property 'match' of ") ||
             error.message.include?("Invalid tag name")
            # This happens if a new version has been published that relies on
            # subdependencies that have not yet been published.
            raise if resolvable_before_update?(lockfile)

            raise_resolvability_error(error, lockfile)
          end
          if error.message.match?(FORBIDDEN_PACKAGE)
            package_name =
              error.message.match(FORBIDDEN_PACKAGE).
              named_captures["package_req"].
              split(/(?<=\w)\@/).first
            handle_missing_package(package_name, error, lockfile)
          end
          if error.message.match?(UNREACHABLE_GIT)
            dependency_url =
              error.message.match(UNREACHABLE_GIT).
              named_captures.fetch("url")

            raise Dependabot::GitDependenciesNotReachable, dependency_url
          end
          raise
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

        def handle_missing_package(package_name, error, lockfile)
          missing_dep = NpmAndYarn::FileParser.new(
            dependency_files: dependency_files,
            source: nil,
            credentials: credentials
          ).parse.find { |dep| dep.name == package_name }

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

            if top_level_dependencies.any?
              File.write(f.name, f.content)
            else
              File.write(f.name, prepared_npm_lockfile_content(f.content))
            end
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
          if @git_ssh_requirements_to_swap
            return @git_ssh_requirements_to_swap
          end

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

        def prepared_npm_lockfile_content(content)
          JSON.dump(
            remove_dependency_from_npm_lockfile(JSON.parse(content))
          )
        end

        # Duplicated in SubdependencyVersionResolver
        # Remove the dependency we want to update from the lockfile and let
        # npm find the latest resolvable version and fix the lockfile
        def remove_dependency_from_npm_lockfile(npm_lockfile)
          return npm_lockfile unless npm_lockfile.key?("dependencies")

          sub_dependency_names = sub_dependencies.map(&:name)
          dependencies =
            npm_lockfile["dependencies"].
            reject { |key, _| sub_dependency_names.include?(key) }.
            map { |k, v| [k, remove_dependency_from_npm_lockfile(v)] }.
            to_h
          npm_lockfile.merge("dependencies" => dependencies)
        end

        def post_process_npm_lockfile(lockfile_content)
          updated_content = lockfile_content

          # Switch SSH requirements back for git dependencies
          git_ssh_requirements_to_swap.each do |req|
            new_r = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'git+https://\1/')
            old_r = req.gsub(%r{git@(.*?)[:/]}, 'git@\1/')
            updated_content = updated_content.gsub(new_r, old_r)
          end

          # Switch from details back for git dependencies (they will have
          # changed because we locked them)
          git_dependencies_to_lock.each do |_, details|
            next unless details[:from]

            new_r = /"from": "#{Regexp.quote(details[:from])}#[^\"]+"/
            old_r = %("from": "#{details[:from]}")
            updated_content = updated_content.gsub(new_r, old_r)
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

        def npm_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../../..")
          File.join(project_root, "helpers/npm/bin/run.js")
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
