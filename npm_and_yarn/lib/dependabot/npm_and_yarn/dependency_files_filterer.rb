# typed: strict
# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"
require "sorbet-runtime"

# Used in the version resolver and file updater to only run yarn/npm helpers on
# dependency files that require updates. This is useful for large monorepos with
# lots of sub-projects that don't all have the same dependencies.
module Dependabot
  module NpmAndYarn
    class DependencyFilesFilterer
      extend T::Sig

      sig { params(dependency_files: T::Array[DependencyFile], updated_dependencies: T::Array[Dependency]).void }
      def initialize(dependency_files:, updated_dependencies:)
        @dependency_files = dependency_files
        @updated_dependencies = updated_dependencies
      end

      sig { returns(T::Array[String]) }
      def paths_requiring_update_check
        @paths_requiring_update_check ||= T.let(fetch_paths_requiring_update_check, T.nilable(T::Array[String]))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def files_requiring_update
        @files_requiring_update ||= T.let(
          dependency_files.select do |file|
            package_files_requiring_update.include?(file) ||
              package_required_lockfile?(file) ||
              workspaces_lockfile?(file)
          end, T.nilable(T::Array[DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def package_files_requiring_update
        @package_files_requiring_update ||= T.let(
          dependency_files.select do |file|
            dependency_manifest_requirements.include?(file.name)
          end, T.nilable(T::Array[DependencyFile])
        )
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T::Array[Dependency]) }
      attr_reader :updated_dependencies

      sig { returns(T::Array[String]) }
      def fetch_paths_requiring_update_check
        # if only a root lockfile exists, it tracks all dependencies
        return [File.dirname(T.must(root_lockfile).name)] if lockfiles == [root_lockfile]

        package_files_requiring_update.map do |file|
          File.dirname(file.name)
        end
      end

      sig { returns(T::Array[String]) }
      def dependency_manifest_requirements
        @dependency_manifest_requirements ||= T.let(
          updated_dependencies.flat_map do |dep|
            dep.requirements.map { |requirement| requirement[:file] }
          end, T.nilable(T::Array[String])
        )
      end

      sig { params(lockfile: DependencyFile).returns(T::Boolean) }
      def package_required_lockfile?(lockfile)
        return false unless lockfile?(lockfile)

        package_files_requiring_update.any? do |package_file|
          File.dirname(package_file.name) == File.dirname(lockfile.name)
        end
      end

      sig { params(lockfile: DependencyFile).returns(T::Boolean) }
      def workspaces_lockfile?(lockfile)
        return false unless ["yarn.lock", "package-lock.json", "pnpm-lock.yaml"].include?(lockfile.name)

        return false unless parsed_root_package_json["workspaces"] || dependency_files.any? do |file|
          file.name.end_with?("pnpm-workspace.yaml") && File.dirname(file.name) == File.dirname(lockfile.name)
        end

        updated_dependencies_in_lockfile?(lockfile)
      end

      sig { returns(T.nilable(DependencyFile)) }
      def root_lockfile
        @root_lockfile ||= T.let(
          lockfiles.find do |file|
            File.dirname(file.name) == "."
          end, T.nilable(DependencyFile)
        )
      end

      sig { returns(T::Array[DependencyFile]) }
      def lockfiles
        @lockfiles ||= T.let(
          dependency_files.select do |file|
            lockfile?(file)
          end, T.nilable(T::Array[DependencyFile])
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_root_package_json
        @parsed_root_package_json ||= T.let(
          begin
            package = T.must(dependency_files.find { |f| f.name == "package.json" })
            JSON.parse(T.must(package.content))
          end, T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { params(lockfile: Dependabot::DependencyFile).returns(T::Boolean) }
      def updated_dependencies_in_lockfile?(lockfile)
        lockfile_dependencies(lockfile).any? do |sub_dep|
          updated_dependencies.any? do |updated_dep|
            sub_dep.name == updated_dep.name
          end
        end
      end

      sig { params(lockfile: DependencyFile).returns(T::Array[Dependency]) }
      def lockfile_dependencies(lockfile)
        @lockfile_dependencies ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependency]]))
        @lockfile_dependencies[lockfile.name] ||=
          NpmAndYarn::FileParser::LockfileParser.new(
            dependency_files: [lockfile]
          ).parse
      end

      sig { params(file: DependencyFile).returns(T::Boolean) }
      def manifest?(file)
        file.name.end_with?("package.json")
      end

      sig { params(file: DependencyFile).returns(T::Boolean) }
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
