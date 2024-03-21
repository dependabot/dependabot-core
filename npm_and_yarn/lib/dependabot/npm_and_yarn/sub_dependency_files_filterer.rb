# typed: strict
# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/npm_and_yarn/version"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"
require "sorbet-runtime"

# Used in the sub dependency version resolver and file updater to only run
# yarn/npm helpers on dependency files that require updates. This is useful for
# large monorepos with lots of sub-projects that don't all have the same
# dependencies.
module Dependabot
  module NpmAndYarn
    class SubDependencyFilesFilterer
      extend T::Sig

      sig { params(dependency_files: T::Array[DependencyFile], updated_dependencies: T::Array[Dependency]).void }
      def initialize(dependency_files:, updated_dependencies:)
        @dependency_files = dependency_files
        @updated_dependencies = updated_dependencies
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def files_requiring_update
        return T.must(@files_requiring_update) if defined? @files_requiring_update

        files_requiring_update =
          lockfiles.select do |lockfile|
            lockfile_dependencies(lockfile).any? do |sub_dep|
              updated_dependencies.any? do |updated_dep|
                next false unless sub_dep.name == updated_dep.name

                version_class.new(updated_dep.version) >
                  version_class.new(sub_dep.version)
              end
            end
          end


        @files_requiring_update ||= T.let(files_requiring_update, T.nilable(T::Array[DependencyFile]))
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T::Array[Dependency]) }
      attr_reader :updated_dependencies

      sig { params(lockfile: DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def lockfile_dependencies(lockfile)
        @lockfile_dependencies ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependency]]))
        @lockfile_dependencies[lockfile.name] ||=
          NpmAndYarn::FileParser::LockfileParser.new(
            dependency_files: [lockfile]
          ).parse
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def lockfiles
        dependency_files.select { |file| lockfile?(file) }
      end

      sig { params(file: DependencyFile).returns(T::Boolean)}
      def lockfile?(file)
        file.name.end_with?(
          "package-lock.json",
          "yarn.lock",
          "npm-shrinkwrap.json",
          "pnpm-lock.yaml"
        )
      end

      sig { returns(T.class_of(Dependabot::NpmAndYarn::Version)) }
      def version_class
        NpmAndYarn::Version
      end
    end
  end
end
