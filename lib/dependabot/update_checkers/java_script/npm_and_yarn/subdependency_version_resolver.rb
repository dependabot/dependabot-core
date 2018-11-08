# frozen_string_literal: true

require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/file_parsers/java_script/npm_and_yarn"
require "dependabot/utils/java_script/version"
require "dependabot/shared_helpers"
require "dependabot/errors"

file_updater_path = "dependabot/file_updaters/java_script/npm_and_yarn/"
require "#{file_updater_path}/npmrc_builder"
require "#{file_updater_path}/package_json_preparer"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn
        class SubdependencyVersionResolver
          def initialize(dependency:, credentials:, dependency_files:,
                         ignored_versions:)
            @dependency       = dependency
            @credentials      = credentials
            @dependency_files = dependency_files
            @ignored_versions = ignored_versions
          end

          def latest_resolvable_version
            # TODO: Update subdependencies for npm lockfiles
            return if package_locks.any? || shrinkwraps.any?

            updated_lockiles = yarn_locks.map do |yarn_lock|
              updated_content = update_subdependency_in_lockfile(yarn_lock)
              updated_lockfile = yarn_lock.dup
              updated_lockfile.content = updated_content
              updated_lockfile
            end

            version_from_updated_lockfiles(updated_lockiles)
          end

          private

          attr_reader :dependency, :credentials, :dependency_files,
                      :ignored_versions

          def update_subdependency_in_lockfile(yarn_lock)
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              updated_files =
                run_yarn_updater(path: Pathname.new(yarn_lock.name).dirname)

              updated_files.fetch("yarn.lock")
            end
          end

          def version_from_updated_lockfiles(updated_lockfiles)
            updated_files = dependency_files -
                            yarn_locks -
                            package_locks -
                            shrinkwraps +
                            updated_lockfiles

            updated_version = FileParsers::JavaScript::NpmAndYarn.new(
              dependency_files: updated_files,
              source: nil,
              credentials: credentials
            ).parse.find { |d| d.name == dependency.name }&.version
            return unless updated_version

            version_class.new(updated_version)
          end

          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/PerceivedComplexity
          def run_yarn_updater(path:)
            SharedHelpers.with_git_configured(credentials: credentials) do
              Dir.chdir(path) do
                SharedHelpers.run_helper_subprocess(
                  command: "node #{yarn_helper_path}",
                  function: "updateSubdependency",
                  args: [Dir.pwd, dependency.name]
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

          def write_temporary_dependency_files
            yarn_locks.each do |f|
              FileUtils.mkdir_p(Pathname.new(f.name).dirname)
              File.write(f.name, prepared_yarn_lockfile_content(f.content))
            end

            File.write(".npmrc", npmrc_content)

            package_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(file.name, prepared_package_json_content(file))
            end
          end

          def prepared_yarn_lockfile_content(content)
            content.gsub(/^#{Regexp.quote(dependency.name)}\@.*?\n\n/m, "")
          end

          def prepared_package_json_content(file)
            FileUpdaters::JavaScript::NpmAndYarn::PackageJsonPreparer.new(
              package_json_content: file.content
            ).prepared_content
          end

          def npmrc_content
            FileUpdaters::JavaScript::NpmAndYarn::NpmrcBuilder.new(
              credentials: credentials,
              dependency_files: dependency_files
            ).npmrc_content
          end

          def version_class
            Utils::JavaScript::Version
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
