# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/swift/file_updater/lockfile_updater"
require "dependabot/swift/file_updater/manifest_updater"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /Package(@swift-\d(\.\d){0,2})?\.swift/,
          /^Package\.resolved$/
        ]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
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

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        # For now we will be updating a single dependency.
        # TODO: Revisit when/if implementing full unlocks
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        raise "A Package.swift file must be provided!" unless manifest
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
