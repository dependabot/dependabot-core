# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  module NpmAndYarn
    class DependencyFilesFilterer
      def initialize(dependency_files:, dependencies:)
        @dependencies = dependencies
        @dependency_files = dependency_files
      end

      def filtered_files
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

      def filtered_package_files
        filtered_files.select { |f| manifest?(f) }
      end

      def filtered_lockfiles
        filtered_files.select { |f| lockfile?(f) }
      end

      private

      attr_reader :dependency_files, :dependencies

      def dependency_manifest_requirements
        @dependency_manifest_requirements ||=
          dependencies.flat_map do |dep|
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
