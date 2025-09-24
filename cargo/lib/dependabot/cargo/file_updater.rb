# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/git_commit_checker"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module Cargo
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/manifest_updater"
      require_relative "file_updater/lockfile_updater"
      require_relative "file_updater/workspace_manifest_updater"

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /Cargo\.toml$/, # Matches Cargo.toml in the root directory or any subdirectory
          /Cargo\.lock$/  # Matches Cargo.lock in the root directory or any subdirectory
        ]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        # Returns an array of updated files. Only files that have been updated
        # should be returned.
        updated_files = []

        manifest_files.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(
              file: file,
              content: updated_manifest_content(file)
            )
        end

        if lockfile && updated_lockfile_content != T.must(lockfile).content
          updated_files <<
            updated_file(file: T.must(lockfile), content: updated_lockfile_content)
        end

        raise "No files changed!" if updated_files.empty?

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        raise "No Cargo.toml!" unless get_original_file("Cargo.toml")
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_manifest_content(file)
        # Use workspace updater for root workspace manifests
        if workspace_root_manifest?(file)
          WorkspaceManifestUpdater.new(
            dependencies: dependencies,
            manifest: file
          ).updated_manifest_content
        else
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: file
          ).updated_manifest_content
        end
      end

      sig { returns(String) }
      def updated_lockfile_content
        @updated_lockfile_content ||= T.let(
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_lockfile_content,
          T.nilable(String)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifest_files
        @manifest_files ||= T.let(
          dependency_files
          .select { |f| f.name.end_with?("Cargo.toml") }
          .reject(&:support_file?),
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(get_original_file("Cargo.lock"), T.nilable(Dependabot::DependencyFile))
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def workspace_root_manifest?(file)
        return false unless file.name == "Cargo.toml"

        parsed_file = TomlRB.parse(file.content)
        parsed_file.key?("workspace") && parsed_file["workspace"].key?("dependencies")
      rescue TomlRB::ParseError
        false
      end
    end
  end
end

Dependabot::FileUpdaters.register("cargo", Dependabot::Cargo::FileUpdater)
