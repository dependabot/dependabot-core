# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/npm_and_yarn/file_updater/npmrc_builder"
require "dependabot/npm_and_yarn/file_updater/package_json_preparer"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class DependencyFilesBuilder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { void }
        def write_temporary_dependency_files
          write_lockfiles

          if Helpers.yarn_berry?(yarn_locks.first)
            File.write(".yarnrc.yml", yarnrc_yml_content) if yarnrc_yml_file
          else
            File.write(".npmrc", npmrc_content)
            File.write(".yarnrc", yarnrc_content) if yarnrc_specifies_private_reg?
          end

          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, prepared_package_json_content(file))
          end
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
        def yarn_locks
          @yarn_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("yarn.lock") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def pnpm_locks
          @pnpm_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("pnpm-lock.yaml") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def bun_locks
          @bun_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("bun.lock") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def root_yarn_lock
          @root_yarn_lock ||= T.let(
            dependency_files
            .find { |f| f.name == "yarn.lock" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def root_pnpm_lock
          @root_pnpm_lock ||= T.let(
            dependency_files
            .find { |f| f.name == "pnpm-lock.yaml" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def root_bun_lock
          @root_bun_lock ||= T.let(
            dependency_files
            .find { |f| f.name == "bun.lock" },
            T.nilable(Dependabot::DependencyFile)
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
        def lockfiles
          [*package_locks, *shrinkwraps, *yarn_locks, *pnpm_locks, *bun_locks]
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_files
          @package_files ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("package.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { void }
        def write_lockfiles
          yarn_locks.each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, prepared_yarn_lockfile_content(T.must(f.content)))
          end

          [*package_locks, *shrinkwraps, *pnpm_locks, *bun_locks].each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, f.content)
          end
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T::Boolean) }
        def yarnrc_specifies_private_reg?
          return false unless yarnrc_file

          regex = Package::RegistryFinder::YARN_GLOBAL_REGISTRY_REGEX
          yarnrc_global_registry =
            yarnrc_file&.content
                       &.lines
                       &.find { |line| line.match?(regex) }
                       &.match(regex)
                       &.named_captures
                       &.fetch("registry")

          return false unless yarnrc_global_registry

          Package::RegistryFinder::CENTRAL_REGISTRIES.none? do |r|
            r.include?(T.must(URI(yarnrc_global_registry).host))
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity

        # Duplicated in NpmLockfileUpdater
        # Remove the dependency we want to update from the lockfile and let
        # yarn find the latest resolvable version and fix the lockfile
        sig { params(content: String).returns(String) }
        def prepared_yarn_lockfile_content(content)
          content.gsub(/^#{Regexp.quote(dependency.name)}\@.*?\n\n/m, "")
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def prepared_package_json_content(file)
          NpmAndYarn::FileUpdater::PackageJsonPreparer.new(
            package_json_content: T.must(file.content)
          ).prepared_content
        end

        sig { returns(String) }
        def npmrc_content
          NpmAndYarn::FileUpdater::NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def yarnrc_file
          dependency_files.find { |f| f.name == ".yarnrc" }
        end

        sig { returns(String) }
        def yarnrc_content
          NpmAndYarn::FileUpdater::NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).yarnrc_content
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def yarnrc_yml_file
          dependency_files.find { |f| f.name.end_with?(".yarnrc.yml") }
        end

        sig { returns(T.nilable(String)) }
        def yarnrc_yml_content
          yarnrc_yml_file&.content
        end
      end
    end
  end
end
