# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Composer
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/manifest_updater"
      require_relative "file_updater/lockfile_updater"

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /^composer\.json$/,
          /^composer\.lock$/
        ]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        if file_changed?(T.must(composer_json))
          updated_files <<
            updated_file(
              file: T.must(composer_json),
              content: updated_composer_json_content
            )
        end

        if lockfile
          updated_files <<
            updated_file(file: T.must(lockfile), content: updated_lockfile_content)
        end

        if updated_files.none? ||
           updated_files.sort_by(&:name) == dependency_files.sort_by(&:name)
          raise "No files have changed!"
        end

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        raise "No #{PackageManager::MANIFEST_FILENAME}!" unless get_original_file(PackageManager::MANIFEST_FILENAME)
      end

      sig { returns(String) }
      def updated_composer_json_content
        ManifestUpdater.new(
          dependencies: dependencies,
          manifest: T.must(composer_json)
        ).updated_manifest_content
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

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def composer_json
        @composer_json ||= T.let(
          get_original_file(PackageManager::MANIFEST_FILENAME),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(get_original_file(PackageManager::LOCKFILE_FILENAME), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end

Dependabot::FileUpdaters.register("composer", Dependabot::Composer::FileUpdater)
