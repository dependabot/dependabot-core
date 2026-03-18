# typed: strong
# frozen_string_literal: true

require "dependabot/experiments"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/swift/file_updater/lockfile_updater"
require "dependabot/swift/file_updater/manifest_updater"
require "dependabot/swift/file_updater/xcode_lockfile_updater"
require "dependabot/swift/xcode_file_helpers"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        if xcode_spm_mode?
          updated_xcode_spm_files
        else
          updated_classic_spm_files
        end
      end

      private

      # Classic SPM update: uses swift CLI to resolve and update
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_classic_spm_files
        updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        SharedHelpers.in_a_temporary_repo_directory(T.must(manifest).directory, repo_contents_path) do
          updated_manifest = T.let(nil, T.nilable(Dependabot::DependencyFile))

          if file_changed?(T.must(manifest))
            updated_manifest = updated_file(file: T.must(manifest), content: updated_manifest_content)
            updated_files << updated_manifest
          end

          if lockfile
            updated_files << updated_file(file: T.must(lockfile), content: updated_lockfile_content(updated_manifest))
          end
        end

        updated_files
      end

      # Xcode SPM update: updates Package.resolved files in-place without CLI
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_xcode_spm_files
        updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        xcode_resolved_files.each do |resolved_file|
          updater = XcodeLockfileUpdater.new(
            resolved_file: resolved_file,
            dependencies: dependencies,
            workspace_files: xcode_workspace_files
          )

          next unless updater.lockfile_changed?

          updated_content = updater.updated_lockfile_content
          next if updated_content == resolved_file.content

          updated_files << updated_file(file: resolved_file, content: updated_content)
        end

        if updated_files.empty?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "No Package.resolved files needed updating for the specified dependencies"
          )
        end

        updated_files
      end

      sig { returns(Dependabot::Dependency) }
      def dependency
        # For now we will be updating a single dependency.
        # TODO: Revisit when/if implementing full unlocks
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        return if manifest
        return if xcode_spm_mode? && xcode_resolved_files.any?

        raise "A Package.swift file or Xcode Package.resolved must be provided!"
      end

      sig { returns(T::Boolean) }
      def xcode_spm_mode?
        return false unless Dependabot::Experiments.enabled?(:enable_swift_xcode_spm)

        manifest.nil? && xcode_resolved_files.any?
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def xcode_resolved_files
        @xcode_resolved_files ||= T.let(
          dependency_files.select do |f|
            XcodeFileHelpers.xcode_resolved_path?(f.name) &&
              !f.support_file?
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def xcode_workspace_files
        @xcode_workspace_files ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?("contents.xcworkspacedata") && f.support_file?
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(String) }
      def updated_manifest_content
        ManifestUpdater.new(
          T.must(T.must(manifest).content),
          old_requirements: T.must(dependency.previous_requirements),
          new_requirements: dependency.requirements
        ).updated_manifest_content
      end

      sig { params(updated_manifest: T.nilable(Dependabot::DependencyFile)).returns(String) }
      def updated_lockfile_content(updated_manifest)
        LockfileUpdater.new(
          dependency: dependency,
          manifest: T.must(updated_manifest || manifest),
          repo_contents_path: T.must(repo_contents_path),
          credentials: credentials,
          target_version: dependency.version
        ).updated_lockfile_content
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest
        @manifest ||= T.let(
          get_original_file("Package.swift"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        return @lockfile if defined?(@lockfile)

        @lockfile = T.let(
          get_original_file("Package.resolved"),
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("swift", Dependabot::Swift::FileUpdater)
