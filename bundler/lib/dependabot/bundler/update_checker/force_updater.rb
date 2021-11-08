# frozen_string_literal: true

require "dependabot/bundler/file_parser"
require "dependabot/bundler/file_updater/lockfile_updater"
require "dependabot/bundler/native_helpers"
require "dependabot/bundler/helpers"
require "dependabot/bundler/update_checker"
require "dependabot/bundler/update_checker/requirements_updater"
require "dependabot/errors"
require "dependabot/shared_helpers"

module Dependabot
  module Bundler
    class UpdateChecker
      class ForceUpdater
        require_relative "shared_bundler_helpers"
        include SharedBundlerHelpers

        def initialize(dependency:, dependency_files:, repo_contents_path: nil,
                       credentials:, target_version:,
                       requirements_update_strategy:,
                       update_multiple_dependencies: true,
                       options:)
          @dependency                   = dependency
          @dependency_files             = dependency_files
          @repo_contents_path           = repo_contents_path
          @credentials                  = credentials
          @target_version               = target_version
          @requirements_update_strategy = requirements_update_strategy
          @update_multiple_dependencies = update_multiple_dependencies
          @options                      = options
        end

        def updated_dependencies
          @updated_dependencies ||= force_update
        end

        private

        attr_reader :dependency, :dependency_files, :repo_contents_path,
                    :credentials, :target_version, :requirements_update_strategy,
                    :options

        def update_multiple_dependencies?
          @update_multiple_dependencies
        end

        def force_update
          in_a_native_bundler_context(error_handling: false) do |tmp_dir|
            updated_deps, specs = NativeHelpers.run_bundler_subprocess(
              bundler_version: bundler_version,
              function: "force_update",
              options: options,
              args: {
                dir: tmp_dir,
                dependency_name: dependency.name,
                target_version: target_version,
                credentials: credentials,
                gemfile_name: gemfile.name,
                lockfile_name: lockfile.name,
                update_multiple_dependencies: update_multiple_dependencies?
              }
            )
            dependencies_from(updated_deps, specs)
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          msg = e.error_class + " with message: " + e.message
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        def original_dependencies
          @original_dependencies ||=
            FileParser.new(
              dependency_files: dependency_files,
              credentials: credentials,
              source: nil
            ).parse
        end

        def dependencies_from(updated_deps, specs)
          # You might think we'd want to remove dependencies whose version
          # hadn't changed from this array. We don't. We still need to unlock
          # them to get Bundler to resolve, because unlocking them is what
          # updates their subdependencies.
          #
          # This is kind of a bug in Bundler, and we should try to fix it,
          # but resolving it won't necessarily be easy.
          updated_deps.map do |dep|
            original_dep =
              original_dependencies.find { |d| d.name == dep.fetch("name") }
            spec = specs.find { |d| d.fetch("name") == dep.fetch("name") }

            next if spec.fetch("version") == original_dep.version

            build_dependency(original_dep, spec)
          end.compact
        end

        def build_dependency(original_dep, updated_spec)
          Dependency.new(
            name: updated_spec.fetch("name"),
            version: updated_spec.fetch("version"),
            requirements:
              RequirementsUpdater.new(
                requirements: original_dep.requirements,
                update_strategy: requirements_update_strategy,
                updated_source: source_for(original_dep),
                latest_version: updated_spec.fetch("version"),
                latest_resolvable_version: updated_spec.fetch("version")
              ).updated_requirements,
            previous_version: original_dep.version,
            previous_requirements: original_dep.requirements,
            package_manager: original_dep.package_manager
          )
        end

        def source_for(dependency)
          dependency.requirements.
            find { |r| r.fetch(:source) }&.
            fetch(:source)
        end

        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end

        def lockfile
          dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        def sanitized_lockfile_body
          re = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
          lockfile.content.gsub(re, "")
        end

        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          File.write(lockfile.name, sanitized_lockfile_body) if lockfile
        end

        def bundler_version
          @bundler_version ||= Helpers.bundler_version(lockfile)
        end
      end
    end
  end
end
