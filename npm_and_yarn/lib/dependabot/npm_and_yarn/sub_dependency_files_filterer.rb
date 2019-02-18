# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/version"

# Used in the sub dependency version resolver and file updater to only run
# yarn/npm helpers on dependency files that require updates. This is useful for
# large monorepos with lots of sub-projects that don't all have the same
# dependencies.
module Dependabot
  module NpmAndYarn
    class SubDependencyFilesFilterer
      def initialize(dependency_files:, updated_dependencies:)
        @dependency_files = dependency_files
        @updated_dependencies = updated_dependencies
      end

      def files_requiring_update
        lockfiles.select do |lockfile|
          sub_dependencies(lockfile).any? do |sub_dep|
            updated_dependencies.any? do |updated_dep|
              next false unless sub_dep.name == updated_dep.name

              version_class.new(updated_dep.version) >
                version_class.new(sub_dep.version)
            end
          end
        end
      end

      private

      attr_reader :dependency_files, :updated_dependencies

      def sub_dependencies(lockfile)
        # Add dummy_package_manifest to keep existing validation login in base
        # file parser
        NpmAndYarn::FileParser.new(
          dependency_files: [dummy_package_manifest, lockfile],
          source: nil,
          credentials: [] # Credentials are only needed for top level deps
        ).parse
      end

      def lockfiles
        @lockfiles ||= dependency_files.select { |file| lockfile?(file) }
      end

      def dummy_package_manifest
        @dummy_package_manifest ||= Dependabot::DependencyFile.new(
          content: "{}",
          name: "package.json"
        )
      end

      def lockfile?(file)
        file.name.end_with?(
          "package-lock.json",
          "yarn.lock",
          "npm-shrinkwrap.json"
        )
      end

      def version_class
        NpmAndYarn::Version
      end
    end
  end
end
