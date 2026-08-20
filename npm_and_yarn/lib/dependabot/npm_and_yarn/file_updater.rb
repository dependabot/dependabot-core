# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/file_updaters/vendor_updater"
require "dependabot/file_updaters/artifact_updater"
require "dependabot/errors"
require "dependabot/package/release_cooldown_options"
require "dependabot/update_checkers/cooldown_calculation"
require "dependabot/npm_and_yarn/dependency_files_filterer"
require "dependabot/npm_and_yarn/sub_dependency_files_filterer"
require "dependabot/npm_and_yarn/version"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base # rubocop:disable Metrics/ClassLength
      extend T::Sig

      require_relative "file_updater/package_json_updater"
      require_relative "file_updater/npm_lockfile_updater"
      require_relative "file_updater/yarn_lockfile_updater"
      require_relative "file_updater/pnpm_lockfile_updater"
      require_relative "file_updater/pnpm_workspace_updater"

      class NoChangeError < StandardError
        extend T::Sig
        include Dependabot::HasSentryContext

        sig { params(message: String, error_context: T::Hash[Symbol, T.anything]).void }
        def initialize(message:, error_context:)
          super(message)
          @error_context = error_context
        end

        sig { override.returns(T::Hash[Symbol, T.anything]) }
        def sentry_context
          { extra: @error_context }
        end
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

        handle_pnpm_support_file_no_change!(updated_files)

        if updated_files.none?
          raise NoChangeError.new(
            message: "No files were updated! Package manager: #{detected_package_manager}",
            error_context: error_context(updated_files: updated_files)
          )
        end

        sorted_updated_files = updated_files.sort_by(&:name)
        if sorted_updated_files == filtered_dependency_files.sort_by(&:name)
          raise NoChangeError.new(
            message: "Updated files are unchanged! Package manager: #{detected_package_manager}",
            error_context: error_context(updated_files: updated_files)
          )
        end

        vendor_updated_files(updated_files)
      end

      private

      sig { params(updated_files: T::Array[DependencyFile]).void }
      def handle_pnpm_support_file_no_change!(updated_files)
        # Also handle all-support-file updates for pnpm workspaces — this can
        # happen when pnpm-workspace.yaml and pnpm-lock.yaml are fetched from a
        # parent directory (marked support_file=true by
        # fetch_file_from_parent_directories). In that case the updated files
        # would be filtered out by DependencyChangeBuilder, so we surface the
        # underlying pnpm misconfiguration.
        return unless original_pnpm_locks.any?
        return unless updated_files.none? || updated_files.all?(&:support_file?)

        raise_miss_configured_tooling_if_pnpm_subdirectory
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { void }
      def raise_miss_configured_tooling_if_pnpm_subdirectory
        workspace_files = original_pnpm_workspace
        lockfiles = original_pnpm_locks

        return if workspace_files.empty?
        return if workspace_files.any? { |f| f.directory == "/" }
        return unless workspace_files.all? { |f| f.name.match?(%r{\A(\.\./)+pnpm-workspace\.yaml\z}) }

        return if lockfiles.empty?
        return if lockfiles.any? { |f| f.directory == "/" }
        return unless lockfiles.all? { |f| f.name.match?(%r{\A(\.\./)+pnpm-lock\.yaml\z}) }

        # Updating a workspace from a subdirectory is unsupported when both
        # pnpm files are sourced from parent directories.
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
        vendor_updater.updated_vendor_cache_files(base_directory: base_dir).each do |file|
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
          end,
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { override.void }
      def check_required_files
        raise DependencyFileNotFound.new(nil, "package.json not found.") unless get_original_file("package.json")
      end

      sig { params(updated_files: T::Array[DependencyFile]).returns(T::Hash[Symbol, T.anything]) }
      def error_context(updated_files:)
        {
          dependencies: dependencies.map(&:to_h),
          updated_files: updated_files.map(&:name),
          dependency_files: dependency_files.map(&:name),
          package_manager: detected_package_manager
        }
      end

      sig { returns(String) }
      def detected_package_manager
        return "npm" if package_locks.any?
        return "yarn" if yarn_locks.any?
        return "pnpm" if pnpm_locks.any?

        "unknown"
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
          begin
            files = filtered_dependency_files.select { |f| f.name.end_with?("package.json") }

            if files.empty? && dependencies.none?(&:top_level?)
              files = dependency_files
                      .select { |f| f.name.end_with?("package.json") }
                      .select { |f| package_json_has_override_for_deps?(f) }
            end

            files
          end,
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { params(package_json: Dependabot::DependencyFile).returns(T::Boolean) }
      def package_json_has_override_for_deps?(package_json)
        parsed = JSON.parse(T.must(package_json.content))
        entries = parsed["resolutions"] || parsed["overrides"] || parsed.dig("pnpm", "overrides") || {}
        return false unless entries.is_a?(Hash)

        dependencies.any? do |dep|
          entries.any? { |k, v| v.is_a?(String) && (k == dep.name || k.end_with?("/#{dep.name}")) }
        end
      rescue JSON::ParserError
        false
      end

      sig { params(yarn_lock: Dependabot::DependencyFile).returns(T::Boolean) }
      def yarn_lock_changed?(yarn_lock)
        yarn_lock.content != updated_yarn_lock_content(yarn_lock)
      end

      sig { params(pnpm_lock: Dependabot::DependencyFile).returns(T::Boolean) }
      def pnpm_lock_changed?(pnpm_lock)
        pnpm_lock.content != updated_pnpm_lock_content(pnpm_lock)
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

        package_locks.each do |package_lock|
          lockfile_updates = updated_lockfile_files(package_lock)
          next if lockfile_updates.empty?

          updated_files.concat(lockfile_updates)
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

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Dependabot::DependencyFile]) }
      def updated_lockfile_files(file)
        return [] unless package_lock_changed?(file)

        updated_file_set = [updated_file(
          file: file,
          content: T.must(updated_lockfile_content(file))
        )]

        already_updated_names = updated_manifest_files.to_set(&:name)

        workspace_package_json_updates(file).each do |manifest_file, updated_content|
          next if updated_content == manifest_file.content
          next if already_updated_names.include?(manifest_file.name)

          updated_file_set << updated_file(file: manifest_file, content: updated_content)
        end

        updated_file_set
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

      # The number of days from the dependabot.yml `cooldown` config to apply as
      # a release-age floor for *transitive* dependencies. npm, pnpm and yarn each
      # enforce this natively at install time, which is the only point at which
      # Dependabot can constrain the versions the package manager resolves for the
      # transitive tree. Returns nil for security updates (which must never be
      # blocked by a release-age gate) or when no positive cooldown is configured.
      #
      # The native gates are a single global value per invocation, so they cannot
      # express per-semver-type days or include/exclude patterns. Passing a value
      # stricter than the rule that selected a version makes the package manager
      # refuse the install it was just asked to perform, which surfaces as a skipped
      # update or a hung resolver (dependabot/dependabot-core#15937). The gate is
      # therefore the *smallest* of the per-update cooldown days, so it never
      # exceeds the window any of the selected versions was approved under.
      #
      # The smallest is deliberately the opposite of the highest-wins rule in
      # `Helpers.higher_release_age_gate`: that reconciles two *competing* policies
      # (ours and the user's), whereas these are all windows we applied ourselves,
      # and taking the highest would reject the update selected under the shortest.
      #
      # A global flag cannot express `include`/`exclude`, and selection gives an
      # excluded dependency a zero-day window, so any gate at all could reject a
      # version it approved. The gate is therefore skipped unless every dependency
      # in the invocation is cooldown-included.
      sig { returns(T.nilable(Integer)) }
      def cooldown_release_age_days
        return nil if options.fetch(:security_updates_only, false)

        cooldown = T.cast(
          options[:update_cooldown],
          T.nilable(Dependabot::Package::ReleaseCooldownOptions)
        )
        return nil if cooldown.nil?
        return nil if dependencies.empty?
        return nil unless dependencies.all? { |dep| cooldown.included?(dep.name) }

        days = dependencies.map { |dep| selection_cooldown_days(cooldown, dep) }.min
        days&.positive? ? days : nil
      end

      # The cooldown window the update checker applied when it selected this
      # dependency's target version, so the native gate can never reject a version
      # Dependabot itself chose. Falls back to `default_days` for versions we cannot
      # parse, matching how `CooldownCalculation` treats an unknown current version.
      sig do
        params(
          cooldown: Dependabot::Package::ReleaseCooldownOptions,
          dependency: Dependabot::Dependency
        ).returns(Integer)
      end
      def selection_cooldown_days(cooldown, dependency)
        new_version = parsed_version(dependency.version)
        return cooldown.default_days if new_version.nil?

        semver_days = Dependabot::UpdateCheckers::CooldownCalculation.cooldown_days_for(
          cooldown,
          parsed_version(dependency.previous_version),
          new_version
        )

        # A dependency absent from the lockfile is selected under `default_days`,
        # because the checker has no current version, yet `previous_version` is
        # later inferred from the manifest requirement. Capping keeps the gate from
        # exceeding whichever of the two windows selection actually used.
        [semver_days, cooldown.default_days].min
      end

      sig { params(version: T.nilable(String)).returns(T.nilable(Dependabot::NpmAndYarn::Version)) }
      def parsed_version(version)
        return nil unless version && Dependabot::NpmAndYarn::Version.correct?(version)

        Dependabot::NpmAndYarn::Version.new(version)
      end

      sig { returns(Dependabot::NpmAndYarn::FileUpdater::YarnLockfileUpdater) }
      def yarn_lockfile_updater
        @yarn_lockfile_updater ||= T.let(
          YarnLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials,
            security_updates_only: options.fetch(:security_updates_only, false) ? true : false,
            release_age_days: cooldown_release_age_days
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
            credentials: credentials,
            security_updates_only: options.fetch(:security_updates_only, false) ? true : false,
            release_age_days: cooldown_release_age_days
          ),
          T.nilable(Dependabot::NpmAndYarn::FileUpdater::PnpmLockfileUpdater)
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(NpmLockfileUpdater) }
      def npm_lockfile_updater_for(file)
        @npm_lockfile_updaters ||= T.let(
          {},
          T.nilable(T::Hash[String, NpmLockfileUpdater])
        )
        @npm_lockfile_updaters[file.name] ||= NpmLockfileUpdater.new(
          lockfile: file,
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials,
          security_updates_only: options.fetch(:security_updates_only, false) ? true : false,
          release_age_days: cooldown_release_age_days
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_lockfile_content(file)
        npm_lockfile_updater_for(file).updated_lockfile.content
      end

      sig do
        params(file: Dependabot::DependencyFile)
          .returns(T::Hash[Dependabot::DependencyFile, String])
      end
      def workspace_package_json_updates(file)
        npm_lockfile_updater_for(file).updated_package_json_files
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
