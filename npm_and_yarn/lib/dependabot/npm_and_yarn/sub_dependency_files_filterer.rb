# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/npm_and_yarn/version"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"

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
        @files_requiring_update ||=
          begin
            lockfiles.select do |lockfile|
              lockfile_dependencies(lockfile).any? do |sub_dep|
                updated_dependencies.any? do |updated_dep|
                  next false unless sub_dep.name == updated_dep.name

                  version_class.new(updated_dep.version) >
                    version_class.new(sub_dep.version)
                end
              end
            end
          end
      end

      private

      attr_reader :dependency_files, :updated_dependencies

      def lockfile_dependencies(lockfile)
        @lockfile_dependencies ||= {}
        @lockfile_dependencies[lockfile.name] ||=
          NpmAndYarn::FileParser::LockfileParser.new(
            dependency_files: [lockfile]
          ).parse
      end

      def lockfiles
        dependency_files.select { |file| lockfile?(file) }
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
