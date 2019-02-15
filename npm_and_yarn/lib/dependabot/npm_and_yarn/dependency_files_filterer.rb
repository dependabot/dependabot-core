# frozen_string_literal: true

require "dependabot/utils"

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

      def files_requiring_update
        dependency_files.select do |file|
          if manifest?(file)
            package_manifests.include?(file)
          elsif lockfile?(file)
            package_manifests.any? do |package_file|
              File.dirname(package_file.name) == File.dirname(file.name)
            end
          else
            # Include all non-manifest/lockfiles
            # e.g. .npmrc, lerna.json
            true
          end
        end
      end

      def package_files_requiring_update
        files_requiring_update.select { |file| manifest?(file) }
      end

      private

      attr_reader :dependency_files, :updated_dependencies

      def dependency_manifest_requirements
        @dependency_manifest_requirements ||=
          updated_dependencies.flat_map do |dep|
            dep.requirements.map { |requirement| requirement[:file] }
          end
      end

      def package_manifests
        @package_manifests ||=
          dependency_files.select do |file|
            next unless manifest?(file)

            root_manifest?(file) ||
              dependency_manifest_requirements.include?(file.name)
          end
      end

      def root_manifest?(file)
        file.name == "package.json"
      end

      def manifest?(file)
        file.name.end_with?("package.json")
      end

      def lockfile?(file)
        file.name.end_with?(
          "package-lock.json",
          "yarn.lock",
          "npm-shrinkwrap.json"
        )
      end
    end
  end
end
