# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/file_updaters/vendor_updater"
require "dependabot/file_updaters/artifact_updater"
require "dependabot/bun/dependency_files_filterer"
require "dependabot/bun/sub_dependency_files_filterer"
require "sorbet-runtime"

module Dependabot
  module Bun
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/package_json_updater"
      require_relative "file_updater/bun_lockfile_updater"

      class NoChangeError < StandardError
        extend T::Sig

        sig { params(message: String, error_context: T::Hash[Symbol, T.untyped]).void }
        def initialize(message:, error_context:)
          super(message)
          @error_context = error_context
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def sentry_context
          { extra: @error_context }
        end
      end

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          %r{^(?:.*\/)?package\.json$},
          %r{^(?:.*\/)?bun\.lock$}
        ]
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def updated_dependency_files
        perform_update
      rescue NoChangeError => e
        raise Dependabot::DependencyFileContentNotChanged, e.message
      end

      sig { returns(T::Array[DependencyFile]) }
      def perform_update
        updated_files = T.let([], T::Array[DependencyFile])

        updated_files += updated_manifest_files
        updated_files += updated_lockfiles

        if updated_files.none?

          raise NoChangeError.new(
            message: "No files were updated!",
            error_context: error_context(updated_files: updated_files)
          )
        end

        sorted_updated_files = updated_files.sort_by(&:name)
        if sorted_updated_files == filtered_dependency_files.sort_by(&:name)
          raise NoChangeError.new(
            message: "Updated files are unchanged!",
            error_context: error_context(updated_files: updated_files)
          )
        end

        vendor_updated_files(updated_files)
      end

      private

      sig { params(updated_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
      def vendor_updated_files(updated_files)
        base_dir = T.must(updated_files.first).directory
        pnp_updater.updated_files(base_directory: base_dir, only_paths: [".pnp.cjs", ".pnp.data.json"]).each do |file|
          updated_files << file
        end

        updated_files
      end

      sig { returns(Dependabot::FileUpdaters::ArtifactUpdater) }
      def pnp_updater
        Dependabot::FileUpdaters::ArtifactUpdater.new(
          repo_contents_path: repo_contents_path,
          target_directory: "./"
        )
      end

      sig { returns(T::Array[DependencyFile]) }
      def filtered_dependency_files
        @filtered_dependency_files ||= T.let(
          if dependencies.any?(&:top_level?)
            DependencyFilesFilterer.new(
              dependency_files: dependency_files,
              updated_dependencies: dependencies
            ).files_requiring_update
          else
            SubDependencyFilesFilterer.new(
              dependency_files: dependency_files,
              updated_dependencies: dependencies
            ).files_requiring_update
          end,
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { override.void }
      def check_required_files
        raise DependencyFileNotFound.new(nil, "package.json not found.") unless get_original_file("package.json")
      end

      sig { params(updated_files: T::Array[DependencyFile]).returns(T::Hash[Symbol, T.untyped]) }
      def error_context(updated_files:)
        {
          dependencies: dependencies.map(&:to_h),
          updated_files: updated_files.map(&:name),
          dependency_files: dependency_files.map(&:name)
        }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def bun_locks
        @bun_locks ||= T.let(
          filtered_dependency_files
          .select { |f| f.name.end_with?("bun.lock") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def package_files
        @package_files ||= T.let(
          filtered_dependency_files.select do |f|
            f.name.end_with?("package.json")
          end,
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { params(bun_lock: Dependabot::DependencyFile).returns(T::Boolean) }
      def bun_lock_changed?(bun_lock)
        bun_lock.content != updated_bun_lock_content(bun_lock)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_manifest_files
        package_files.filter_map do |file|
          updated_content = updated_package_json_content(file)
          next if updated_content == file.content

          updated_file(file: file, content: T.must(updated_content))
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_lockfiles
        updated_files = []

        bun_locks.each do |bun_lock|
          next unless bun_lock_changed?(bun_lock)

          updated_files << updated_file(
            file: bun_lock,
            content: updated_bun_lock_content(bun_lock)
          )
        end

        updated_files
      end

      sig { params(bun_lock: Dependabot::DependencyFile).returns(String) }
      def updated_bun_lock_content(bun_lock)
        @updated_bun_lock_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
        @updated_bun_lock_content[bun_lock.name] ||=
          bun_lockfile_updater.updated_bun_lock_content(bun_lock)
      end

      sig { returns(Dependabot::Bun::FileUpdater::BunLockfileUpdater) }
      def bun_lockfile_updater
        @bun_lockfile_updater ||= T.let(
          BunLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: T.must(repo_contents_path),
            credentials: credentials
          ),
          T.nilable(Dependabot::Bun::FileUpdater::BunLockfileUpdater)
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_package_json_content(file)
        @updated_package_json_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
        @updated_package_json_content[file.name] ||=
          PackageJsonUpdater.new(
            package_json: file,
            dependencies: dependencies
          ).updated_package_json.content
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("bun", Dependabot::Bun::FileUpdater)
