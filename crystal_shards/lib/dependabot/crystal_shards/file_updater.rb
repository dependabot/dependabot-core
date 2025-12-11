# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "open3"
require "fileutils"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/crystal_shards/package_manager"

module Dependabot
  module CrystalShards
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/manifest_updater"
      require_relative "file_updater/lockfile_updater"

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        manifest = manifest_file
        if manifest_changed?(manifest)
          updated_files << updated_file(
            file: manifest,
            content: updated_manifest_content(manifest)
          )
        end

        lock = lockfile
        if lock && lockfile_changed?(lock)
          updated_files << updated_file(
            file: lock,
            content: updated_lockfile_content
          )
        end

        raise "No files changed!" if updated_files.empty?

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        return if shard_yml

        raise "No #{MANIFEST_FILE}"
      end

      sig { returns(Dependabot::DependencyFile) }
      def manifest_file
        file = shard_yml
        raise "No #{MANIFEST_FILE}" unless file

        file
      end

      sig { params(manifest: Dependabot::DependencyFile).returns(T::Boolean) }
      def manifest_changed?(manifest)
        updated_manifest_content(manifest) != manifest.content
      end

      sig { params(lock: Dependabot::DependencyFile).returns(T::Boolean) }
      def lockfile_changed?(lock)
        updated_lockfile_content != lock.content
      end

      sig { params(manifest: Dependabot::DependencyFile).returns(String) }
      def updated_manifest_content(manifest)
        @updated_manifest_content ||= T.let(
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: manifest
          ).updated_manifest_content,
          T.nilable(String)
        )
      end

      sig { returns(String) }
      def updated_lockfile_content
        @updated_lockfile_content ||= T.let(
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: updated_dependency_files_for_lockfile,
            credentials: credentials
          ).updated_lockfile_content,
          T.nilable(String)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files_for_lockfile
        files = dependency_files.dup
        manifest = manifest_file

        if manifest_changed?(manifest)
          files = files.reject { |f| f.name == MANIFEST_FILE }
          files << updated_file(
            file: manifest,
            content: updated_manifest_content(manifest)
          )
        end

        files
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def shard_yml
        @shard_yml ||= T.let(
          get_original_file(MANIFEST_FILE),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          get_original_file(LOCKFILE),
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileUpdaters.register("crystal_shards", Dependabot::CrystalShards::FileUpdater)
