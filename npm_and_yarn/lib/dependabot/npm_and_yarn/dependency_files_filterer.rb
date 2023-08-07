# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"

# Used in the version resolver and file updater to only run yarn/npm helpers on
# dependency files that require updates. This is useful for large monorepos with
# lots of sub-projects that don't all have the same dependencies.
module Dependabot
  module NpmAndYarn
    class DependencyFilesFilterer
      def initialize(dependency_files:, updated_dependencies:)
        @dependency_files = dependency_files
        @updated_dependencies = updated_dependencies
      end

      def paths_requiring_update_check
        @paths_requiring_update_check ||= fetch_paths_requiring_update_check
      end

      def files_requiring_update
        @files_requiring_update ||=
          dependency_files.select do |file|
            package_files_requiring_update.include?(file) ||
              package_required_lockfile?(file) ||
              workspaces_lockfile?(file)
          end
      end

      def package_files_requiring_update
        @package_files_requiring_update ||=
          dependency_files.select do |file|
            dependency_manifest_requirements.include?(file.name)
          end
      end

      private

      attr_reader :dependency_files, :updated_dependencies

      def fetch_paths_requiring_update_check
        # if only a root lockfile exists, it tracks all dependencies
        return [File.dirname(root_lockfile.name)] if lockfiles == [root_lockfile]

        package_files_requiring_update.map do |file|
          File.dirname(file.name)
        end
      end

      def dependency_manifest_requirements
        @dependency_manifest_requirements ||=
          updated_dependencies.flat_map do |dep|
            dep.requirements.map { |requirement| requirement[:file] }
          end
      end

      def package_required_lockfile?(lockfile)
        return false unless lockfile?(lockfile)

        package_files_requiring_update.any? do |package_file|
          File.dirname(package_file.name) == File.dirname(lockfile.name)
        end
      end

      def workspaces_lockfile?(lockfile)
        return false unless ["yarn.lock", "package-lock.json", "pnpm-lock.yaml"].include?(lockfile.name)

        return false unless parsed_root_package_json["workspaces"] || dependency_files.any? do |file|
          file.name.end_with?("pnpm-workspace.yaml") && File.dirname(file.name) == File.dirname(lockfile.name)
        end

        updated_dependencies_in_lockfile?(lockfile)
      end

      def root_lockfile
        @root_lockfile ||=
          lockfiles.find do |file|
            File.dirname(file.name) == "."
          end
      end

      def lockfiles
        @lockfiles ||=
          dependency_files.select do |file|
            lockfile?(file)
          end
      end

      def parsed_root_package_json
        @parsed_root_package_json ||=
          begin
            package = dependency_files.find { |f| f.name == "package.json" }
            JSON.parse(package.content)
          end
      end

      def updated_dependencies_in_lockfile?(lockfile)
        lockfile_dependencies(lockfile).any? do |sub_dep|
          updated_dependencies.any? do |updated_dep|
            sub_dep.name == updated_dep.name
          end
        end
      end

      def lockfile_dependencies(lockfile)
        @lockfile_dependencies ||= {}
        @lockfile_dependencies[lockfile.name] ||=
          NpmAndYarn::FileParser::LockfileParser.new(
            dependency_files: [lockfile]
          ).parse
      end

      def manifest?(file)
        file.name.end_with?("package.json")
      end

      def lockfile?(file)
        file.name.end_with?(
          "package-lock.json",
          "yarn.lock",
          "pnpm-lock.yaml",
          "npm-shrinkwrap.json"
        )
      end
    end
  end
end
