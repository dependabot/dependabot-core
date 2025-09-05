# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
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
        extend T::Sig

        require_relative "shared_bundler_helpers"

        include SharedBundlerHelpers

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            target_version: Dependabot::Version,
            requirements_update_strategy: Dependabot::RequirementsUpdateStrategy,
            options: T::Hash[Symbol, T.untyped],
            repo_contents_path: T.nilable(String),
            update_multiple_dependencies: T::Boolean
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:, target_version:,
                       requirements_update_strategy:, options:,
                       repo_contents_path: nil,
                       update_multiple_dependencies: true)
          @dependency                   = dependency
          @dependency_files             = dependency_files
          @repo_contents_path           = repo_contents_path
          @credentials                  = credentials
          @target_version               = target_version
          @requirements_update_strategy = requirements_update_strategy
          @update_multiple_dependencies = update_multiple_dependencies
          @options                      = options

          @updated_dependencies         = T.let(nil, T.nilable(T::Array[Dependabot::Dependency]))
          @original_dependencies        = T.let(nil, T.nilable(T::Array[Dependabot::Dependency]))
          @bundler_version              = T.let(nil, T.nilable(String))
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def updated_dependencies
          @updated_dependencies ||= force_update
        end

        # Abstract method implementations
        sig { override.returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { override.returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { override.returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :options

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(Dependabot::Version) }
        attr_reader :target_version

        sig { returns(Dependabot::RequirementsUpdateStrategy) }
        attr_reader :requirements_update_strategy

        sig { returns(T::Boolean) }
        def update_multiple_dependencies?
          @update_multiple_dependencies
        end

        # rubocop:disable Metrics/AbcSize
        sig { returns(T::Array[Dependabot::Dependency]) }
        def force_update
          requirement = dependency.requirements.find { |req| req[:file] == T.must(gemfile).name }

          valid_gem_version?(target_version)

          manifest_requirement_not_satisfied = requirement && !Requirement.satisfied_by?(requirement, target_version)

          if manifest_requirement_not_satisfied && requirements_update_strategy.lockfile_only?
            raise Dependabot::DependencyFileNotResolvable
          end

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
                gemfile_name: T.must(gemfile).name,
                lockfile_name: T.must(lockfile).name,
                update_multiple_dependencies: update_multiple_dependencies?
              }
            )
            dependencies_from(updated_deps, specs)
          rescue SharedHelpers::HelperSubprocessFailed => e
            msg = e.error_class + " with message: " + e.message
            raise Dependabot::DependencyFileNotResolvable, msg
          end
        end
        # rubocop:enable Metrics/AbcSize

        sig { params(target_version: T.nilable(Dependabot::Version)).returns(TrueClass) }
        def valid_gem_version?(target_version)
          # to rule out empty, non gem info ending up in as target_version
          return true if target_version.is_a?(Gem::Version)

          Dependabot.logger.warn("Bundler force update called with a non-Gem::Version #{target_version}")

          raise Dependabot::DependencyFileNotResolvable
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def original_dependencies
          @original_dependencies ||=
            FileParser.new(
              dependency_files: dependency_files,
              credentials: credentials,
              source: nil
            ).parse
        end

        sig do
          params(
            updated_deps: T::Array[T::Hash[String, T.untyped]],
            specs: T::Array[T::Hash[String, T.untyped]]
          )
            .returns(T::Array[Dependabot::Dependency])
        end
        def dependencies_from(updated_deps, specs)
          # You might think we'd want to remove dependencies whose version
          # hadn't changed from this array. We don't. We still need to unlock
          # them to get Bundler to resolve, because unlocking them is what
          # updates their subdependencies.
          #
          # This is kind of a bug in Bundler, and we should try to fix it,
          # but resolving it won't necessarily be easy.
          updated_deps.filter_map do |dep|
            original_dep =
              original_dependencies.find { |d| d.name == dep.fetch("name") }
            spec = specs.find { |d| d.fetch("name") == dep.fetch("name") }

            next if T.must(spec).fetch("version") == T.must(original_dep).version

            build_dependency(original_dep, spec)
          end
        end

        sig { params(original_dep: T.untyped, updated_spec: T.untyped).returns(Dependabot::Dependency) }
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

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(T::Hash[String, T.untyped])) }
        def source_for(dependency)
          dependency.requirements
                    .find { |r| r.fetch(:source) }
                    &.fetch(:source)
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        sig { returns(String) }
        def sanitized_lockfile_body
          re = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
          T.must(T.must(lockfile).content).gsub(re, "")
        end

        sig { void }
        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          File.write(T.must(lockfile).name, sanitized_lockfile_body) if lockfile
        end

        sig { override.returns(String) }
        def bundler_version
          @bundler_version ||= Helpers.bundler_version(lockfile)
        end
      end
    end
  end
end
