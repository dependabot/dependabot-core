# frozen_string_literal: true

require "dependabot/npm_and_yarn/update_checker"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/version"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/npm_and_yarn/file_updater/npmrc_builder"
require "dependabot/npm_and_yarn/file_updater/package_json_preparer"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class SubdependencyVersionResolver
        def initialize(dependency:, credentials:, dependency_files:,
                       ignored_versions:)
          @dependency       = dependency
          @credentials      = credentials
          @dependency_files = dependency_files
          @ignored_versions = ignored_versions
        end

        def latest_resolvable_version
          raise "Not a subdependency!" if dependency.requirements.any?

          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            updated_lockfiles = lockfiles.map do |lockfile|
              updated_content = update_subdependency_in_lockfile(lockfile)
              updated_lockfile = lockfile.dup
              updated_lockfile.content = updated_content
              updated_lockfile
            end

            version_from_updated_lockfiles(updated_lockfiles)
          end
        rescue SharedHelpers::HelperSubprocessFailed
          # TODO: Move error handling logic from the FileUpdater to this class

          # Return nil (no update possible) if an unknown error occurred
          nil
        end

        private

        attr_reader :dependency, :credentials, :dependency_files,
                    :ignored_versions

        def update_subdependency_in_lockfile(lockfile)
          lockfile_name = Pathname.new(lockfile.name).basename.to_s
          path = Pathname.new(lockfile.name).dirname.to_s

          updated_files = if lockfile.name.end_with?("yarn.lock")
                            run_yarn_updater(path, lockfile_name)
                          else
                            run_npm_updater(path, lockfile_name)
                          end

          updated_files.fetch(lockfile_name)
        end

        def version_from_updated_lockfiles(updated_lockfiles)
          updated_files = dependency_files -
                          yarn_locks -
                          package_locks -
                          shrinkwraps +
                          updated_lockfiles

          updated_version = NpmAndYarn::FileParser.new(
            dependency_files: updated_files,
            source: nil,
            credentials: credentials
          ).parse.find { |d| d.name == dependency.name }&.version
          return unless updated_version

          version_class.new(updated_version)
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def run_yarn_updater(path, lockfile_name)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              SharedHelpers.run_helper_subprocess(
                command: "node #{yarn_helper_path}",
                function: "updateSubdependency",
                args: [Dir.pwd, lockfile_name]
              )
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => error
          unfindable_str = "find package \"#{dependency.name}"
          raise unless error.message.include?("The registry may be down") ||
                       error.message.include?("ETIMEDOUT") ||
                       error.message.include?("ENOBUFS") ||
                       error.message.include?(unfindable_str)

          retry_count ||= 0
          retry_count += 1
          raise if retry_count > 2

          sleep(rand(3.0..10.0)) && retry
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def run_npm_updater(path, lockfile_name)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              SharedHelpers.run_helper_subprocess(
                command: "node #{npm_helper_path}",
                function: "updateSubdependency",
                args: [Dir.pwd, lockfile_name]
              )
            end
          end
        end

        def write_temporary_dependency_files
          write_lock_files

          File.write(".npmrc", npmrc_content)

          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, prepared_package_json_content(file))
          end
        end

        def write_lock_files
          yarn_locks.each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, prepared_yarn_lockfile_content(f.content))
          end

          [*package_locks, *shrinkwraps].each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, prepared_npm_lockfile_content(f.content))
          end
        end

        # Duplicated in NpmLockfileUpdater
        # Remove the dependency we want to update from the lockfile and let
        # yarn find the latest resolvable version and fix the lockfile
        def prepared_yarn_lockfile_content(content)
          content.gsub(/^#{Regexp.quote(dependency.name)}\@.*?\n\n/m, "")
        end

        def prepared_npm_lockfile_content(content)
          JSON.dump(
            remove_dependency_from_npm_lockfile(JSON.parse(content))
          )
        end

        # Duplicated in NpmLockfileUpdater
        # Remove the dependency we want to update from the lockfile and let
        # npm find the latest resolvable version and fix the lockfile
        def remove_dependency_from_npm_lockfile(npm_lockfile)
          return npm_lockfile unless npm_lockfile.key?("dependencies")

          dependencies =
            npm_lockfile["dependencies"].
            reject { |key, _| key == dependency.name }.
            map { |k, v| [k, remove_dependency_from_npm_lockfile(v)] }.
            to_h
          npm_lockfile.merge("dependencies" => dependencies)
        end

        def prepared_package_json_content(file)
          NpmAndYarn::FileUpdater::PackageJsonPreparer.new(
            package_json_content: file.content
          ).prepared_content
        end

        def npmrc_content
          NpmAndYarn::FileUpdater::NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content
        end

        def version_class
          NpmAndYarn::Version
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

        def lockfiles
          [*package_locks, *shrinkwraps, *yarn_locks]
        end

        def package_files
          @package_files ||=
            dependency_files.
            select { |f| f.name.end_with?("package.json") }
        end

        def yarn_helper_path
          NativeHelpers.yarn_helper_path
        end

        def npm_helper_path
          NativeHelpers.npm_helper_path
        end
      end
    end
  end
end
