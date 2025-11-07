# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Bazel
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/bzlmod_file_updater"
      require_relative "file_updater/workspace_file_updater"
      require_relative "file_updater/declaration_parser"

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /^MODULE\.bazel$/,
          %r{^(?:.*/)?[^/]+\.MODULE\.bazel$},
          /^MODULE\.bazel\.lock$/,
          %r{^(?:.*/)?MODULE\.bazel\.lock$},
          /^WORKSPACE$/,
          %r{^(?:.*/)?WORKSPACE\.bazel$},
          %r{^(?:.*/)?BUILD$},
          %r{^(?:.*/)?BUILD\.bazel$}
        ]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        dependencies.each do |dependency|
          if bzlmod_dependency?(dependency)
            updated_files.concat(update_bzlmod_dependency(dependency))
          elsif workspace_dependency?(dependency)
            updated_files.concat(update_workspace_dependency(dependency))
          end
        end

        updated_files.uniq
      end

      private

      sig { override.void }
      def check_required_files
        return if module_files.any? || workspace_files.any?

        raise Dependabot::DependencyFileNotFound.new(
          nil,
          "No MODULE.bazel or WORKSPACE file found!"
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def module_files
        @module_files ||= T.let(
          dependency_files.select { |f| f.name.end_with?("MODULE.bazel") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def workspace_files
        @workspace_files ||= T.let(
          dependency_files.select do |f|
            f.name == "WORKSPACE" || f.name.end_with?("WORKSPACE.bazel")
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def lockfile_files
        @lockfile_files ||= T.let(
          dependency_files.select { |f| f.name.end_with?("MODULE.bazel.lock") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Boolean) }
      def requires_lockfile_update?
        dependencies.any? { |dep| bzlmod_dependency?(dep) }
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
      def bzlmod_dependency?(dependency)
        dependency.requirements.any? { |req| req[:file]&.end_with?("MODULE.bazel") }
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
      def workspace_dependency?(dependency)
        dependency.requirements.any? do |req|
          req[:file] == "WORKSPACE" || req[:file]&.end_with?("WORKSPACE.bazel")
        end
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Array[Dependabot::DependencyFile]) }
      def update_bzlmod_dependency(dependency)
        bzlmod_updater = BzlmodFileUpdater.new(
          dependency_files: dependency_files,
          dependencies: [dependency],
          credentials: credentials
        )
        bzlmod_updater.updated_module_files
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Array[Dependabot::DependencyFile]) }
      def update_workspace_dependency(dependency)
        workspace_updater = WorkspaceFileUpdater.new(
          dependency_files: dependency_files,
          dependencies: [dependency],
          credentials: credentials
        )
        workspace_updater.updated_workspace_files
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def relevant_dependencies_for_file(file)
        dependencies.select do |dependency|
          dependency.package_manager == "bazel" &&
            dependency.requirements.any? { |req| req[:file] == file.name }
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register("bazel", Dependabot::Bazel::FileUpdater)
