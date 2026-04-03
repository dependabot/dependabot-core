# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/shared_helpers"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/file_updaters/vendor_updater"

module Dependabot
  module GoModules
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/go_mod_updater"

      # NOTE: repo_contents_path is typed as T.nilable(String) to maintain
      # compatibility with the base FileUpdater class signature. However,
      # we validate it's not nil at runtime since it's always required in production.
      sig do
        override
          .params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String),
            options: T::Hash[Symbol, T.untyped]
          )
          .void
      end
      def initialize(dependencies:, dependency_files:, credentials:, repo_contents_path: nil, options: {})
        super

        raise ArgumentError, "repo_contents_path is required" if repo_contents_path.nil?
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        if workspace?
          # Handle workspace mode - update all workspace module files
          updated_files.concat(updated_workspace_module_files)
        elsif go_mod && dependency_changed?(T.must(go_mod))
          # Single module mode
          updated_files <<
            updated_file(
              file: T.must(go_mod),
              content: T.must(file_updater.updated_go_mod_content)
            )

          if go_sum && T.must(go_sum).content != file_updater.updated_go_sum_content
            updated_files <<
              updated_file(
                file: T.must(go_sum),
                content: T.must(file_updater.updated_go_sum_content)
              )
          end

          vendor_updater.updated_files(base_directory: T.must(directory))
                        .each do |file|
            updated_files << file
          end
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { params(go_mod: Dependabot::DependencyFile).returns(T::Boolean) }
      def dependency_changed?(go_mod)
        # file_changed? only checks for changed requirements. Need to check for indirect dep version changes too.
        file_changed?(go_mod) || dependencies.any? { |dep| dep.previous_version != dep.version }
      end

      sig { override.void }
      def check_required_files
        return if go_mod || go_work

        raise "No go.mod or go.work!"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        @go_mod ||= T.let(get_original_file("go.mod"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_sum
        @go_sum ||= T.let(get_original_file("go.sum"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_work
        @go_work ||= T.let(get_original_file("go.work"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Boolean) }
      def workspace?
        !go_work.nil?
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_workspace_module_files
        updated = []
        workspace_files = file_updater.updated_workspace_files

        # Process each workspace module's files
        workspace_files.each do |file_key, content|
          # Convert the file key back to a path
          # e.g., "tools_go.mod" -> "tools/go.mod"
          file_path = file_key.to_s.gsub("_", "/")

          # Find the original file
          original = dependency_files.find { |f| f.name == file_path }
          next unless original

          # Only include if content changed
          if original.content != content
            updated << updated_file(file: original, content: content)
          end
        end

        # Also handle root go.mod and go.sum if present
        if go_mod && file_updater.updated_go_mod_content
          if T.must(go_mod).content != file_updater.updated_go_mod_content
            updated << updated_file(
              file: T.must(go_mod),
              content: T.must(file_updater.updated_go_mod_content)
            )
          end
        end

        if go_sum && file_updater.updated_go_sum_content
          if T.must(go_sum).content != file_updater.updated_go_sum_content
            updated << updated_file(
              file: T.must(go_sum),
              content: T.must(file_updater.updated_go_sum_content)
            )
          end
        end

        updated
      end

      sig { returns(T.nilable(String)) }
      def directory
        dependency_files.first&.directory
      end

      sig { returns(String) }
      def vendor_dir
        File.join(repo_contents_path, directory, "vendor")
      end

      sig { returns(Dependabot::FileUpdaters::VendorUpdater) }
      def vendor_updater
        Dependabot::FileUpdaters::VendorUpdater.new(
          repo_contents_path: repo_contents_path,
          vendor_dir: vendor_dir
        )
      end

      sig { returns(GoModUpdater) }
      def file_updater
        @file_updater ||= T.let(
          GoModUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            directory: T.must(directory),
            options: { tidy: tidy?, vendor: vendor? }
          ),
          T.nilable(Dependabot::GoModules::FileUpdater::GoModUpdater)
        )
      end

      sig { returns(T::Boolean) }
      def tidy?
        true
      end

      sig { returns(T::Boolean) }
      def vendor?
        File.exist?(File.join(vendor_dir, "modules.txt"))
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("go_modules", Dependabot::GoModules::FileUpdater)
