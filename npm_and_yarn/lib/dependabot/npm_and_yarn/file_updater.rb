# typed: true
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/file_updaters/vendor_updater"
require "dependabot/file_updaters/artifact_updater"
require "dependabot/npm_and_yarn/dependency_files_filterer"
require "dependabot/npm_and_yarn/sub_dependency_files_filterer"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/package_json_updater"
      require_relative "file_updater/npm_lockfile_updater"
      require_relative "file_updater/yarn_lockfile_updater"
      require_relative "file_updater/pnpm_lockfile_updater"

      class NoChangeError < StandardError
        def initialize(message:, error_context:)
          super(message)
          @error_context = error_context
        end

        def sentry_context
          { extra: @error_context }
        end
      end

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /^package\.json$/,
          /^package-lock\.json$/,
          /^npm-shrinkwrap\.json$/,
          /^yarn\.lock$/,
          /^pnpm-lock\.yaml$/
        ]
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def updated_dependency_files
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

      def vendor_updated_files(updated_files)
        base_dir = updated_files.first.directory
        pnp_updater.updated_files(base_directory: base_dir, only_paths: [".pnp.cjs", ".pnp.data.json"]).each do |file|
          updated_files << file
        end
        T.unsafe(vendor_updater).updated_vendor_cache_files(base_directory: base_dir).each do |file|
          updated_files << file
        end
        install_state_updater.updated_files(base_directory: base_dir).each do |file|
          updated_files << file
        end

        updated_files
      end

      # Dynamically fetch the vendor cache folder from yarn
      def vendor_cache_dir
        return @vendor_cache_dir if defined?(@vendor_cache_dir)

        @vendor_cache_dir = Helpers.fetch_yarnrc_yml_value("cacheFolder", "./.yarn/cache")
      end

      def install_state_path
        return @install_state_path if defined?(@install_state_path)

        @install_state_path = Helpers.fetch_yarnrc_yml_value("installStatePath", "./.yarn/install-state.gz")
      end

      sig { returns(Dependabot::FileUpdaters::VendorUpdater) }
      def vendor_updater
        Dependabot::FileUpdaters::VendorUpdater.new(
          repo_contents_path: repo_contents_path,
          vendor_dir: vendor_cache_dir
        )
      end

      sig { returns(Dependabot::FileUpdaters::ArtifactUpdater) }
      def install_state_updater
        Dependabot::FileUpdaters::ArtifactUpdater.new(
          repo_contents_path: repo_contents_path,
          target_directory: install_state_path
        )
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
          end, T.nilable(T::Array[DependencyFile])
        )
      end

      sig { override.void }
      def check_required_files
        raise "No package.json!" unless get_original_file("package.json")
      end

      sig { params(updated_files: T::Array[DependencyFile]).returns(T::Hash[Symbol, T.untyped]) }
      def error_context(updated_files:)
        {
          dependencies: dependencies.map(&:to_h),
          updated_files: updated_files.map(&:name),
          dependency_files: dependency_files.map(&:name)
        }
      end

      def package_locks
        @package_locks ||=
          filtered_dependency_files
          .select { |f| f.name.end_with?("package-lock.json") }
      end

      def yarn_locks
        @yarn_locks ||=
          filtered_dependency_files
          .select { |f| f.name.end_with?("yarn.lock") }
      end

      def pnpm_locks
        @pnpm_locks ||=
          filtered_dependency_files
          .select { |f| f.name.end_with?("pnpm-lock.yaml") }
      end

      def shrinkwraps
        @shrinkwraps ||=
          filtered_dependency_files
          .select { |f| f.name.end_with?("npm-shrinkwrap.json") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def package_files
        @package_files ||= T.let(
          filtered_dependency_files.select do |f|
            f.name.end_with?("package.json")
          end, T.nilable(T::Array[DependencyFile])
        )
      end

      def yarn_lock_changed?(yarn_lock)
        yarn_lock.content != updated_yarn_lock_content(yarn_lock)
      end

      def pnpm_lock_changed?(pnpm_lock)
        pnpm_lock.content != updated_pnpm_lock_content(pnpm_lock)
      end

      def package_lock_changed?(package_lock)
        package_lock.content != updated_lockfile_content(package_lock)
      end

      def shrinkwrap_changed?(shrinkwrap)
        shrinkwrap.content != updated_lockfile_content(shrinkwrap)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_manifest_files
        package_files.filter_map do |file|
          updated_content = updated_package_json_content(file)
          next if updated_content == file.content

          updated_file(file: file, content: updated_content)
        end
      end

      def updated_lockfiles
        updated_files = []

        yarn_locks.each do |yarn_lock|
          next unless yarn_lock_changed?(yarn_lock)

          updated_files << updated_file(
            file: yarn_lock,
            content: updated_yarn_lock_content(yarn_lock)
          )
        end

        pnpm_locks.each do |pnpm_lock|
          next unless pnpm_lock_changed?(pnpm_lock)

          updated_files << updated_file(
            file: pnpm_lock,
            content: updated_pnpm_lock_content(pnpm_lock)
          )
        end

        package_locks.each do |package_lock|
          next unless package_lock_changed?(package_lock)

          updated_files << updated_file(
            file: package_lock,
            content: updated_lockfile_content(package_lock)
          )
        end

        shrinkwraps.each do |shrinkwrap|
          next unless shrinkwrap_changed?(shrinkwrap)

          updated_files << updated_file(
            file: shrinkwrap,
            content: updated_lockfile_content(shrinkwrap)
          )
        end

        updated_files
      end

      def updated_yarn_lock_content(yarn_lock)
        @updated_yarn_lock_content ||= {}
        @updated_yarn_lock_content[yarn_lock.name] ||=
          yarn_lockfile_updater.updated_yarn_lock_content(yarn_lock)
      end

      def updated_pnpm_lock_content(pnpm_lock)
        @updated_pnpm_lock_content ||= {}
        @updated_pnpm_lock_content[pnpm_lock.name] ||=
          pnpm_lockfile_updater.updated_pnpm_lock_content(pnpm_lock)
      end

      def yarn_lockfile_updater
        @yarn_lockfile_updater ||=
          YarnLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials
          )
      end

      def pnpm_lockfile_updater
        @pnpm_lockfile_updater ||=
          PnpmLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials
          )
      end

      def updated_lockfile_content(file)
        @updated_lockfile_content ||= {}
        @updated_lockfile_content[file.name] ||=
          NpmLockfileUpdater.new(
            lockfile: file,
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_lockfile.content
      end

      def updated_package_json_content(file)
        @updated_package_json_content ||= {}
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
  .register("npm_and_yarn", Dependabot::NpmAndYarn::FileUpdater)
