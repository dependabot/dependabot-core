# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/swift/file_updater/lockfile_updater"
require "dependabot/swift/file_updater/manifest_updater"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [
          /Package(@swift-\d(\.\d){0,2})?\.swift/,
          /^Package\.resolved$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        SharedHelpers.in_a_temporary_repo_directory(manifest.directory, repo_contents_path) do
          updated_manifest = nil

          if file_changed?(manifest)
            updated_manifest = updated_file(file: manifest, content: updated_manifest_content)
            updated_files << updated_manifest
          end

          updated_files << updated_file(file: lockfile, content: updated_lockfile_content(updated_manifest)) if lockfile
        end

        updated_files
      end

      private

      def dependency
        # For now we will be updating a single dependency.
        # TODO: Revisit when/if implementing full unlocks
        dependencies.first
      end

      def check_required_files
        raise "A Package.swift file must be provided!" unless manifest
      end

      def updated_manifest_content
        ManifestUpdater.new(
          manifest.content,
          old_requirements: dependency.previous_requirements,
          new_requirements: dependency.requirements
        ).updated_manifest_content
      end

      def updated_lockfile_content(updated_manifest)
        LockfileUpdater.new(
          dependencies: dependencies,
          manifest: updated_manifest || manifest,
          repo_contents_path: repo_contents_path,
          credentials: credentials
        ).updated_lockfile_content
      end

      def manifest
        @manifest ||= get_original_file("Package.swift")
      end

      def lockfile
        return @lockfile if defined?(@lockfile)

        @lockfile = get_original_file("Package.resolved")
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("swift", Dependabot::Swift::FileUpdater)
