# frozen_string_literal: true

require "ostruct"

require "dependabot/monkey_patches/bundler/definition_ruby_version_patch"
require "dependabot/monkey_patches/bundler/definition_bundler_version_patch"
require "dependabot/monkey_patches/bundler/git_source_patch"

require "dependabot/bundler/update_checker"
require "dependabot/bundler/update_checker/requirements_updater"
require "dependabot/bundler/file_updater/lockfile_updater"
require "dependabot/bundler/file_parser"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Bundler
    class UpdateChecker
      class ForceUpdater
        def initialize(dependency:, dependency_files:, repo_contents_path: nil,
                       credentials:, target_version:,
                       requirements_update_strategy:,
                       update_multiple_dependencies: true)
          @dependency                   = dependency
          @dependency_files             = dependency_files
          @repo_contents_path           = repo_contents_path
          @credentials                  = credentials
          @target_version               = target_version
          @requirements_update_strategy = requirements_update_strategy
          @update_multiple_dependencies = update_multiple_dependencies
        end

        def updated_dependencies
          @updated_dependencies ||= force_update
        end

        private

        attr_reader :dependency, :dependency_files, :repo_contents_path,
                    :credentials, :target_version, :requirements_update_strategy

        def update_multiple_dependencies?
          @update_multiple_dependencies
        end

        def force_update
          base_directory = dependency_files.first.directory
          SharedHelpers.in_a_temporary_repo_directory(base_directory,
                                                      repo_contents_path) do
            write_temporary_dependency_files

            updated_deps, specs = SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path,
              function: "force_update",
              args: {
                dir: Dir.pwd,
                dependency_name: dependency.name,
                target_version: target_version,
                credentials: relevant_credentials,
                gemfile_name: gemfile.name,
                lockfile_name: lockfile.name,
                using_bundler_2: using_bundler_2?,
                update_multiple_dependencies: update_multiple_dependencies?
              }
            )
            updated_deps = updated_deps.map do |dep_hash|
              OpenStruct.new(dep_hash)
            end
            specs = specs.map do |spec_hash|
              OpenStruct.new(spec_hash)
            end
            dependencies = [dependency] + updated_deps
            dependencies_from(dependencies, specs)
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise Dependabot::DependencyFileNotResolvable, e.message
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
              original_dependencies.find { |d| d.name == dep.name }
            spec = specs.find { |d| d.name == dep.name }

            next if spec.version.to_s == original_dep.version

            build_dependency(original_dep, spec)
          end.compact
        end

        def build_dependency(original_dep, updated_spec)
          Dependency.new(
            name: updated_spec.name,
            version: updated_spec.version,
            requirements:
              RequirementsUpdater.new(
                requirements: original_dep.requirements,
                update_strategy: requirements_update_strategy,
                updated_source: source_for(original_dep),
                latest_version: updated_spec.version,
                latest_resolvable_version: updated_spec.version
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

        def relevant_credentials
          credentials.
            select { |cred| cred["password"] || cred["token"] }.
            select do |cred|
              next true if cred["type"] == "git_source"
              next true if cred["type"] == "rubygems_server"

              false
            end
        end

        def using_bundler_2?
          return unless lockfile

          lockfile.content.match?(/BUNDLED WITH\s+2/m)
        end
      end
    end
  end
end
