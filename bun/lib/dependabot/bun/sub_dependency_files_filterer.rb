# typed: strong
# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/bun/version"
require "dependabot/bun/file_parser/lockfile_parser"
require "sorbet-runtime"

# Used in the sub dependency version resolver and file updater to only run
# yarn/npm helpers on dependency files that require updates. This is useful for
# large monorepos with lots of sub-projects that don't all have the same
# dependencies.
module Dependabot
  module Bun
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
                next true if updated_dep.top_level?

                next false unless updated_dep.version

                updated_version = version_class.new(updated_dep.version)
                candidate_versions_for(sub_dep).any? do |candidate_version|
                  updated_version > candidate_version
                end
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
          Bun::FileParser::LockfileParser.new(
            dependency_files: [lockfile]
          ).parse
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def lockfiles
        dependency_files.select { |file| lockfile?(file) }
      end

      sig { params(file: DependencyFile).returns(T::Boolean) }
      def lockfile?(file)
        file.name.end_with?(
          "package-lock.json",
          "yarn.lock",
          "npm-shrinkwrap.json",
          "bun.lock",
          "pnpm-lock.yaml"
        )
      end

      sig { returns(T.class_of(Dependabot::Bun::Version)) }
      def version_class
        Bun::Version
      end

      sig { params(sub_dep: Dependency).returns(T::Array[Dependabot::Bun::Version]) }
      def candidate_versions_for(sub_dep)
        all_versions = T.cast(sub_dep.metadata[:all_versions], T.nilable(T::Array[Dependency]))
        dependencies = all_versions&.any? ? all_versions : [sub_dep]

        dependencies.filter_map do |dep|
          dep.version && version_class.correct?(dep.version) ? version_class.new(dep.version) : nil
        end
      end
    end
  end
end
