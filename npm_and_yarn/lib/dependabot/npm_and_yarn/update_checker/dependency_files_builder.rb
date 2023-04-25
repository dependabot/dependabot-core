# frozen_string_literal: true

require "dependabot/npm_and_yarn/file_updater/npmrc_builder"
require "dependabot/npm_and_yarn/file_updater/package_json_preparer"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class DependencyFilesBuilder
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
        end

        def write_temporary_dependency_files
          write_lock_files

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

        def pnpm_locks
          @pnpm_locks ||=
            dependency_files.
            select { |f| f.name.end_with?("pnpm-lock.yaml") }
        end

        def root_yarn_lock
          @root_yarn_lock ||=
            dependency_files.
            find { |f| f.name == "yarn.lock" }
        end

        def root_pnpm_lock
          @root_pnpm_lock ||=
            dependency_files.
            find { |f| f.name == "pnpm-lock.yaml" }
        end

        def shrinkwraps
          @shrinkwraps ||=
            dependency_files.
            select { |f| f.name.end_with?("npm-shrinkwrap.json") }
        end

        def lockfiles
          [*package_locks, *shrinkwraps, *yarn_locks, *pnpm_locks]
        end

        def package_files
          @package_files ||=
            dependency_files.
            select { |f| f.name.end_with?("package.json") }
        end

        private

        attr_reader :dependency, :dependency_files, :credentials

        def write_lock_files
          yarn_locks.each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, prepared_yarn_lockfile_content(f.content))
          end

          pnpm_locks.each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, f.content)
          end

          [*package_locks, *shrinkwraps].each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, f.content)
          end
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

          UpdateChecker::RegistryFinder::CENTRAL_REGISTRIES.none? do |r|
            r.include?(URI(yarnrc_global_registry).host)
          end
        end

        # Duplicated in NpmLockfileUpdater
        # Remove the dependency we want to update from the lockfile and let
        # yarn find the latest resolvable version and fix the lockfile
        def prepared_yarn_lockfile_content(content)
          content.gsub(/^#{Regexp.quote(dependency.name)}\@.*?\n\n/m, "")
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

        def yarnrc_file
          dependency_files.find { |f| f.name == ".yarnrc" }
        end

        def yarnrc_content
          NpmAndYarn::FileUpdater::NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).yarnrc_content
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
