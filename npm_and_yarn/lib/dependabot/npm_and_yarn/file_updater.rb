# typed: strict
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
    class FileUpdater < Dependabot::FileUpdaters::Base # rubocop:disable Metrics/ClassLength
      extend T::Sig

      require_relative "file_updater/package_json_updater"
      require_relative "file_updater/npm_lockfile_updater"
      require_relative "file_updater/yarn_lockfile_updater"
      require_relative "file_updater/pnpm_lockfile_updater"
      require_relative "file_updater/bun_lockfile_updater"
      require_relative "file_updater/pnpm_workspace_updater"

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
          %r{^(?:.*/)?package\.json$},
          %r{^(?:.*/)?package-lock\.json$},
          %r{^(?:.*/)?npm-shrinkwrap\.json$},
          %r{^(?:.*/)?yarn\.lock$},
          %r{^(?:.*/)?pnpm-lock\.yaml$},
          %r{^(?:.*/)?pnpm-workspace\.yaml$},
          %r{^(?:.*/)?\.yarn/.*}, # Matches any file within the .yarn/ directory
          %r{^(?:.*/)?\.pnp\.(?:js|cjs)$} # Matches .pnp.js or .pnp.cjs files
        ]
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def updated_dependency_files
        updated_files = T.let([], T::Array[DependencyFile])

        updated_files += updated_manifest_files
        updated_files += if pnpm_workspace.any?
                           update_pnpm_workspace_and_locks
                         else
                           updated_lockfiles
                         end

        if updated_files.none?
          if Dependabot::Experiments.enabled?(:enable_fix_for_pnpm_no_change_error) && original_pnpm_locks.any?
            raise_tool_not_supported_for_pnpm_if_transitive
            raise_miss_configured_tooling_if_pnpm_subdirectory
          end

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

      sig { void }
      def raise_tool_not_supported_for_pnpm_if_transitive
        # ✅ Ensure there are dependencies and check if all are transitive
        return if dependencies.empty? || dependencies.any?(&:top_level?)

        raise ToolFeatureNotSupported.new(
          tool_name: "pnpm",
          tool_type: "package_manager",
          feature: "updating transitive dependencies"
        )
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { void }
      def raise_miss_configured_tooling_if_pnpm_subdirectory
        workspace_files = original_pnpm_workspace
        lockfiles = original_pnpm_locks

        # ✅ Ensure `pnpm-workspace.yaml` is in a parent directory
        return if workspace_files.empty?
        return if workspace_files.any? { |f| f.directory == "/" }
        return unless workspace_files.all? { |f| f.name.end_with?("../pnpm-workspace.yaml") }

        # ✅ Ensure `pnpm-lock.yaml` is also in a parent directory
        return if lockfiles.empty?
        return if lockfiles.any? { |f| f.directory == "/" }
        return unless lockfiles.all? { |f| f.name.end_with?("../pnpm-lock.yaml") }

        # ❌ Raise error → Updating inside a subdirectory is misconfigured
        raise MisconfiguredTooling.new(
          "pnpm",
          "Updating workspaces from inside a workspace subdirectory is not supported. " \
          "Both `pnpm-lock.yaml` and `pnpm-workspace.yaml` exist in a parent directory. " \
          "Dependabot should only update from the root workspace."
        )
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def update_pnpm_workspace_and_locks
        workspace_updates = updated_pnpm_workspace_files
        lock_updates = update_pnpm_locks

        workspace_updates + lock_updates
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def update_pnpm_locks
        updated_files = []
        pnpm_locks.each do |pnpm_lock|
          next unless pnpm_lock_changed?(pnpm_lock)

          updated_files << updated_file(
            file: pnpm_lock,
            content: updated_pnpm_lock_content(pnpm_lock)
          )
        end
        updated_files
      end

      sig { params(updated_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
      def vendor_updated_files(updated_files)
        base_dir = T.must(updated_files.first).directory
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
      sig { returns(String) }
      def vendor_cache_dir
        @vendor_cache_dir ||= T.let(
          Helpers.fetch_yarnrc_yml_value("cacheFolder", "./.yarn/cache"),
          T.nilable(String)
        )
      end

      sig { returns(String) }
      def install_state_path
        @install_state_path ||= T.let(
          Helpers.fetch_yarnrc_yml_value("installStatePath", "./.yarn/install-state.gz"),
          T.nilable(String)
        )
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
      def package_locks
        @package_locks ||= T.let(
          filtered_dependency_files
          .select { |f| f.name.end_with?("package-lock.json") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def yarn_locks
        @yarn_locks ||= T.let(
          filtered_dependency_files
          .select { |f| f.name.end_with?("yarn.lock") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pnpm_locks
        @pnpm_locks ||= T.let(
          filtered_dependency_files
          .select { |f| f.name.end_with?("pnpm-lock.yaml") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pnpm_workspace
        @pnpm_workspace ||= T.let(
          filtered_dependency_files
          .select { |f| f.name.end_with?("pnpm-workspace.yaml") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def original_pnpm_locks
        @original_pnpm_locks ||= T.let(
          dependency_files
          .select { |f| f.name.end_with?("pnpm-lock.yaml") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def original_pnpm_workspace
        @original_pnpm_workspace ||= T.let(
          dependency_files
          .select { |f| f.name.end_with?("pnpm-workspace.yaml") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
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
      def shrinkwraps
        @shrinkwraps ||= T.let(
          filtered_dependency_files
          .select { |f| f.name.end_with?("npm-shrinkwrap.json") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def package_files
        @package_files ||= T.let(
          filtered_dependency_files.select do |f|
            f.name.end_with?("package.json")
          end, T.nilable(T::Array[DependencyFile])
        )
      end

      sig { params(yarn_lock: Dependabot::DependencyFile).returns(T::Boolean) }
      def yarn_lock_changed?(yarn_lock)
        yarn_lock.content != updated_yarn_lock_content(yarn_lock)
      end

      sig { params(pnpm_lock: Dependabot::DependencyFile).returns(T::Boolean) }
      def pnpm_lock_changed?(pnpm_lock)
        pnpm_lock.content != updated_pnpm_lock_content(pnpm_lock)
      end

      sig { params(bun_lock: Dependabot::DependencyFile).returns(T::Boolean) }
      def bun_lock_changed?(bun_lock)
        bun_lock.content != updated_bun_lock_content(bun_lock)
      end

      sig { params(package_lock: Dependabot::DependencyFile).returns(T::Boolean) }
      def package_lock_changed?(package_lock)
        package_lock.content != updated_lockfile_content(package_lock)
      end

      sig { params(shrinkwrap: Dependabot::DependencyFile).returns(T::Boolean) }
      def shrinkwrap_changed?(shrinkwrap)
        shrinkwrap.content != updated_lockfile_content(shrinkwrap)
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
      def updated_pnpm_workspace_files
        pnpm_workspace.filter_map do |file|
          updated_content = updated_pnpm_workspace_content(file)
          next if updated_content == file.content

          updated_file(file: file, content: T.must(updated_content))
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_lockfiles
        updated_files = []

        yarn_locks.each do |yarn_lock|
          next unless yarn_lock_changed?(yarn_lock)

          updated_files << updated_file(
            file: yarn_lock,
            content: updated_yarn_lock_content(yarn_lock)
          )
        end

        updated_files.concat(update_pnpm_locks)

        bun_locks.each do |bun_lock|
          next unless bun_lock_changed?(bun_lock)

          updated_files << updated_file(
            file: bun_lock,
            content: updated_bun_lock_content(bun_lock)
          )
        end

        package_locks.each do |package_lock|
          next unless package_lock_changed?(package_lock)

          updated_files << updated_file(
            file: package_lock,
            content: T.must(updated_lockfile_content(package_lock))
          )
        end

        shrinkwraps.each do |shrinkwrap|
          next unless shrinkwrap_changed?(shrinkwrap)

          updated_files << updated_file(
            file: shrinkwrap,
            content: T.must(updated_lockfile_content(shrinkwrap))
          )
        end

        updated_files
      end
      sig { params(yarn_lock: Dependabot::DependencyFile).returns(String) }
      def updated_yarn_lock_content(yarn_lock)
        @updated_yarn_lock_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
        @updated_yarn_lock_content[yarn_lock.name] ||=
          yarn_lockfile_updater.updated_yarn_lock_content(yarn_lock)
      end

      sig { params(pnpm_lock: Dependabot::DependencyFile).returns(String) }
      def updated_pnpm_lock_content(pnpm_lock)
        @updated_pnpm_lock_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
        @updated_pnpm_lock_content[pnpm_lock.name] ||=
          pnpm_lockfile_updater.updated_pnpm_lock_content(
            pnpm_lock,
            updated_pnpm_workspace_content: @updated_pnpm_workspace_content
          )
      end

      sig { params(bun_lock: Dependabot::DependencyFile).returns(String) }
      def updated_bun_lock_content(bun_lock)
        @updated_bun_lock_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
        @updated_bun_lock_content[bun_lock.name] ||=
          bun_lockfile_updater.updated_bun_lock_content(bun_lock)
      end

      sig { returns(Dependabot::NpmAndYarn::FileUpdater::YarnLockfileUpdater) }
      def yarn_lockfile_updater
        @yarn_lockfile_updater ||= T.let(
          YarnLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials
          ),
          T.nilable(Dependabot::NpmAndYarn::FileUpdater::YarnLockfileUpdater)
        )
      end

      sig { returns(Dependabot::NpmAndYarn::FileUpdater::PnpmLockfileUpdater) }
      def pnpm_lockfile_updater
        @pnpm_lockfile_updater ||= T.let(
          PnpmLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials
          ),
          T.nilable(Dependabot::NpmAndYarn::FileUpdater::PnpmLockfileUpdater)
        )
      end

      sig { returns(Dependabot::NpmAndYarn::FileUpdater::BunLockfileUpdater) }
      def bun_lockfile_updater
        @bun_lockfile_updater ||= T.let(
          BunLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials
          ),
          T.nilable(Dependabot::NpmAndYarn::FileUpdater::BunLockfileUpdater)
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_lockfile_content(file)
        @updated_lockfile_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
        @updated_lockfile_content[file.name] ||=
          NpmLockfileUpdater.new(
            lockfile: file,
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_lockfile.content
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

      sig do
        params(file: Dependabot::DependencyFile)
          .returns(T.nilable(String))
      end
      def updated_pnpm_workspace_content(file)
        @updated_pnpm_workspace_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
        @updated_pnpm_workspace_content[file.name] ||=
          PnpmWorkspaceUpdater.new(
            workspace_file: file,
            dependencies: dependencies
          ).updated_pnpm_workspace.content
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("npm_and_yarn", Dependabot::NpmAndYarn::FileUpdater)
