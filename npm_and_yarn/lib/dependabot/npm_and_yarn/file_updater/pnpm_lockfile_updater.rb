# typed: strong
# frozen_string_literal: true

require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/package/registry_finder"
require "dependabot/npm_and_yarn/registry_parser"
require "dependabot/npm_and_yarn/version"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      # rubocop:disable Metrics/ClassLength
      class PnpmLockfileUpdater
        extend T::Sig

        require_relative "npmrc_builder"
        require "dependabot/npm_and_yarn/pnpm_resolutions"
        require "dependabot/npm_and_yarn/pnpm_workspace_config"
        require_relative "package_json_updater"

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            repo_contents_path: T.nilable(String),
            credentials: T::Array[Dependabot::Credential],
            security_updates_only: T::Boolean,
            release_age_days: T.nilable(Integer)
          ).void
        end
        def initialize(
          dependencies:,
          dependency_files:,
          repo_contents_path:,
          credentials:,
          security_updates_only: false,
          release_age_days: nil
        )
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
          @security_updates_only = security_updates_only
          @unpinned_dependency_names = T.let([], T::Array[String])
          @release_age_days = release_age_days
          @trust_existing_lockfile = T.let(nil, T.nilable(T::Boolean))
          @error_handler = T.let(
            PnpmErrorHandler.new(
              dependencies: dependencies,
              dependency_files: dependency_files
            ),
            PnpmErrorHandler
          )
        end

        sig do
          params(
            pnpm_locks: T::Array[Dependabot::DependencyFile],
            updated_pnpm_workspace_content: T.nilable(T::Hash[String, T.nilable(String)])
          ).returns(T::Hash[String, String])
        end
        def updated_pnpm_lock_contents(pnpm_locks, updated_pnpm_workspace_content: nil)
          @updated_pnpm_lock_content ||= T.let(
            {},
            T.nilable(T::Hash[String, String])
          )
          cache = @updated_pnpm_lock_content
          pending = pnpm_locks.reject { |lock| cache.key?(lock.name) }
          return cache if pending.empty?

          begin
            cache.merge!(
              run_pnpm_update_all(
                pnpm_locks: pending,
                updated_pnpm_workspace_content: updated_pnpm_workspace_content
              )
            )
          rescue SharedHelpers::HelperSubprocessFailed => e
            handle_pnpm_lock_updater_error(e, pending)
          end
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Boolean) }
        def security_updates_only?
          @security_updates_only
        end

        sig { returns(PnpmErrorHandler) }
        attr_reader :error_handler

        IRRESOLVABLE_PACKAGE = "ERR_PNPM_NO_MATCHING_VERSION"
        INVALID_REQUIREMENT = "ERR_PNPM_SPEC_NOT_SUPPORTED_BY_ANY_RESOLVER"

        # pnpm introduced the `minimumReleaseAge` release-age gate in 10.16 and the
        # `minimumReleaseAgeStrict` toggle in 11.0; older versions ignore them.
        PNPM_MINIMUM_RELEASE_AGE_VERSION = "10.16"
        PNPM_MINIMUM_RELEASE_AGE_STRICT_VERSION = "11.0"
        # pnpm 10.x ignores minimumReleaseAge when shared-workspace-lockfile is
        # disabled (pnpm/pnpm#10008); the fix ships in pnpm 11.
        PNPM_WORKSPACE_RELEASE_AGE_FIX_VERSION = "11.0"
        # pnpm 11 stopped reading non-registry settings (e.g. minimum-release-age)
        # from .npmrc, so a .npmrc release-age gate is only effective on pnpm 10.x.
        PNPM_NPMRC_RELEASE_AGE_DROPPED_VERSION = "11.0"
        # `trustLockfile` (pnpm 11.3) skips the verification pass that re-applies
        # minimumReleaseAge/trustPolicy to entries already in the lockfile, without
        # relaxing the gate for versions pnpm resolves now.
        PNPM_TRUST_LOCKFILE_VERSION = "11.3"
        # pnpm-workspace.yaml settings that govern verification of loaded lockfile
        # entries, and so must not be overridden by `trustLockfile=true`.
        LOCKFILE_VERIFICATION_SETTINGS = %w(trustLockfile trustPolicy).freeze
        # `--config.*` keys are passed in kebab-case: pnpm 10.16 through 11.x reads
        # either spelling on the command line, but pnpm 12 silently ignores
        # camelCase there. (pnpm-workspace.yaml is the opposite: every version reads
        # only camelCase keys from it.)
        STRICT_RELEASE_AGE_OFF = "--config.minimum-release-age-strict=false"
        TRUST_LOCKFILE_ON = "--config.trust-lockfile=true"

        UNREACHABLE_GIT = %r{Command failed with exit code 128: git ls-remote (?<url>.*github\.com/[^/]+/[^ ]+)}
        UNREACHABLE_GIT_V8 = %r{ERR_PNPM_FETCH_404[ [^:print]]+GET (?<url>https://codeload\.github\.com/[^/]+/[^/]+)/}
        FORBIDDEN_PACKAGE = /ERR_PNPM_FETCH_403[ [^:print]]+GET (?<dependency_url>.*): Forbidden - 403/
        MISSING_PACKAGE = /ERR_PNPM_FETCH_404[ [^:print]]+GET (?<dependency_url>.*): (?:Not Found)? - 404/
        UNAUTHORIZED_PACKAGE = /ERR_PNPM_FETCH_401[ [^:print]]+GET (?<dependency_url>.*): Unauthorized - 401/

        # ERR_PNPM_FETCH ERROR CODES
        ERR_PNPM_FETCH_401 = /ERR_PNPM_FETCH_401.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_403 = /ERR_PNPM_FETCH_403.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_404 = /ERR_PNPM_FETCH_404.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_500 = /ERR_PNPM_FETCH_500.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_502 = /ERR_PNPM_FETCH_502.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_503 = /ERR_PNPM_FETCH_503.*GET (?<dependency_url>.*):/

        # ERR_PNPM_UNSUPPORTED_ENGINE
        ERR_PNPM_UNSUPPORTED_ENGINE = /ERR_PNPM_UNSUPPORTED_ENGINE/
        PACAKGE_MANAGER = /Your (?<pkg_mgr>.*) version is incompatible with/
        VERSION_REQUIREMENT = /Expected version: (?<supported_ver>.*)\nGot: (?<detected_ver>.*)\n/

        ERR_PNPM_TARBALL_INTEGRITY = /ERR_PNPM_TARBALL_INTEGRITY/

        ERR_PNPM_PATCH_NOT_APPLIED = /ERR_PNPM_PATCH_NOT_APPLIED/

        # this intermittent issue is related with Node v20
        ERR_INVALID_THIS = /ERR_INVALID_THIS/
        URL_SEARCH_PARAMS = /URLSearchParams/

        # A modules directory is present and is linked to a different store directory.
        ERR_PNPM_UNEXPECTED_STORE = /ERR_PNPM_UNEXPECTED_STORE/

        # ERR_PNPM_UNSUPPORTED_PLATFORM
        ERR_PNPM_UNSUPPORTED_PLATFORM = /ERR_PNPM_UNSUPPORTED_PLATFORM/
        PLATFORM_PACAKGE_DEP = /Unsupported platform for (?<dep>.*)\: wanted/
        PLATFORM_VERSION_REQUIREMENT = /wanted {(?<supported_ver>.*)} \(current: (?<detected_ver>.*)\)/
        PLATFORM_PACAKGE_MANAGER = "pnpm"

        INVALID_PACKAGE_SPEC = /Invalid package manager specification/

        # Metadata inconsistent error codes
        ERR_PNPM_META_FETCH_FAIL = /ERR_PNPM_META_FETCH_FAIL/
        ERR_PNPM_BROKEN_METADATA_JSON = /ERR_PNPM_BROKEN_METADATA_JSON/

        # Directory related error codes
        ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND = /ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND*.*Could not install from \"(?<dir>.*)\" /
        ERR_PNPM_WORKSPACE_PKG_NOT_FOUND = /ERR_PNPM_WORKSPACE_PKG_NOT_FOUND/

        # Unparsable package.json file
        ERR_PNPM_INVALID_PACKAGE_JSON = /Invalid package.json in package/

        # Invalid dependency name in package.json
        ERR_PNPM_INVALID_DEPENDENCY_NAME =
          /ERR_PNPM_INVALID_DEPENDENCY_NAME.*invalid name: "(?<dep>[^"]+)"/m

        # Unparsable lockfile
        ERR_PNPM_UNEXPECTED_PKG_CONTENT_IN_STORE = /ERR_PNPM_UNEXPECTED_PKG_CONTENT_IN_STORE/
        ERR_PNPM_OUTDATED_LOCKFILE = /ERR_PNPM_OUTDATED_LOCKFILE/

        # Peer dependencies configuration error
        ERR_PNPM_PEER_DEP_ISSUES = /ERR_PNPM_PEER_DEP_ISSUES/

        # Trust downgrade error (supply chain security)
        ERR_PNPM_TRUST_DOWNGRADE = /ERR_PNPM_TRUST_DOWNGRADE/
        TRUST_DOWNGRADE_PACKAGE = /High-risk trust downgrade for "(?<dep>[^"]+)"/

        sig do
          params(
            pnpm_locks: T::Array[Dependabot::DependencyFile],
            updated_pnpm_workspace_content: T.nilable(T::Hash[String, T.nilable(String)])
          )
            .returns(T::Hash[String, String])
        end
        def run_pnpm_update_all(pnpm_locks:, updated_pnpm_workspace_content: nil)
          # Set dependency files and credentials for automatic env variable injection
          Helpers.dependency_files = dependency_files
          Helpers.credentials = credentials

          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            File.write(".npmrc", workspace_npmrc_content)

            SharedHelpers.with_git_configured(credentials: credentials) do
              # Every fetched lockfile, not just the ones being returned. The
              # update and both fallbacks are workspace-recursive and rewrite
              # every project, so a lockfile left out of this set is one whose
              # churn is never snapshotted, never restored, and still on disk
              # when `store_changes` commits the tree — where the next grouped
              # iteration reads it back as though the repository had always
              # looked that way. `update_pnpm_locks` drops whatever did not
              # actually move.
              requested = pnpm_locks.map(&:name)
              lockfiles_on_entry = lockfile_paths
              names = reachable_lockfile_names(requested, lockfiles_on_entry)
              original_contents = read_lockfiles(names)

              if updated_pnpm_workspace_content
                # Written at the path each one actually has. A catalog updated from
                # inside a member is named `../pnpm-workspace.yaml`, so writing the
                # bare name would leave that member an empty workspace file and
                # resolve nothing against the catalog that moved.
                updated_pnpm_workspace_content.each do |name, content|
                  File.write(name, content) if content
                end
              else
                run_pnpm_update_packages
              end
              # The update checker ran pnpm in this same working tree, so the
              # manifests on disk may not match the dependency files. Write
              # them so `pnpm install` resolves from the intended manifests.
              write_final_package_json_files

              run_pnpm_install

              updated_contents = run_fallbacks(original_contents, read_lockfiles(names), names, requested)
              updated_contents = restore_unrequested(original_contents, updated_contents, names, requested)
              discard_lockfiles_written_here(lockfiles_on_entry)

              verify_importers_retained!(original_contents, updated_contents)

              # After the fallbacks: they resolve without a version too.
              verify_unpinned_updates!(only(original_contents, requested), only(updated_contents, requested))

              updated_contents
            end
          end
        end

        sig do
          params(
            original_contents: T::Hash[String, String],
            updated_contents: T::Hash[String, String],
            names: T::Array[String],
            requested: T::Array[String]
          ).returns(T::Hash[String, String])
        end
        def run_fallbacks(original_contents, updated_contents, names, requested)
          return updated_contents unless Dependabot::Experiments.enabled?(:enable_audit_fix_fallback)

          # One retry per dependency, adopted only where that dependency was owed.
          # The command is workspace-recursive whatever it is asked for, so a
          # project that had already settled this dependency would otherwise take
          # a version-less re-resolution of it on another project's behalf.
          owed_by_dependency(owed_among(original_contents, updated_contents, requested))
            .each do |dep, lockfile_names|
            run_pnpm_deep_update_fallback([dep])
            updated_contents = adopt_fallback_output(updated_contents, names, lockfile_names)
          end

          still_owed = owed_among(original_contents, updated_contents, requested)
          if still_owed.any?
            run_pnpm_audit_fix_fallback(updated_contents)
            updated_contents = adopt_fallback_output(updated_contents, names, still_owed.keys)
          end

          updated_contents
        end

        # Every lockfile the resolution can reach, not only the fetched ones: a
        # committed member lockfile withheld by `exclude_paths` is absent from the
        # dependency files but still on the tree, and the recursive pass rewrites
        # it like any other. `requested` stays the output set.
        #
        # Deduplicated by the file each name reaches rather than by how it is
        # spelled. A job whose directory is a member meets its own lockfile twice:
        # once as the fetched `pnpm-lock.yaml`, and once as the glob's walk back
        # down from the workspace root. `requested` comes first, so the name this
        # update answers for is the one that survives.
        sig { params(requested: T::Array[String], on_entry: T::Array[String]).returns(T::Array[String]) }
        def reachable_lockfile_names(requested, on_entry)
          (requested + workspace_pnpm_locks.map(&:name) + on_entry)
            .uniq { |name| File.expand_path(name) }
        end

        # Lockfile paths on the tree right now.
        sig { returns(T::Array[String]) }
        def lockfile_paths
          Dir.glob(File.join(workspace_root_relative_dir, "**", PNPMPackageManager::LOCKFILE_NAME))
             .map { |path| Pathname.new(path).cleanpath.to_path }
        end

        # Where the workspace root sits relative to the job directory. A job
        # targeting a member resolves siblings above itself, and a glob rooted at
        # the job directory would not see their lockfiles at all — so they would be
        # neither restored nor cleaned up.
        sig { returns(String) }
        def workspace_root_relative_dir
          nearest = workspace_files.min_by { |file| file.name.scan("../").count }
          nearest ? File.dirname(nearest.name) : "."
        end

        # Remove the lockfiles this resolution brought into being.
        #
        # A workspace member that committed none still gets one written for it,
        # because the install is recursive. It is not a file this update returns —
        # it did not exist when the job fetched — but it is left on the tree, and
        # an active `Workspace` commits the whole tree, so it would reach the next
        # grouped iteration as a file no pull request ever mentioned. The member is
        # no worse off for its absence: a project with no committed lockfile
        # already fails `--frozen-lockfile` whatever this update does.
        sig { params(present_on_entry: T::Array[String]).void }
        def discard_lockfiles_written_here(present_on_entry)
          (lockfile_paths - present_on_entry).each { |path| FileUtils.rm_f(path) }
        end

        # Put back the lockfiles this update rewrote but does not return.
        #
        # The primary update is workspace-recursive, so it rewrites every project,
        # not only the ones being read back. `update_pnpm_locks` reports just the
        # requested ones — but in clone mode `Workspace.store_change` commits the
        # whole dirty tree, so churn in the rest would reach the next grouped
        # iteration as though the repository had always looked that way, in a file
        # no pull request ever mentioned. Restore them on disk and in the result,
        # the way fallback adoption already restores what it must not keep.
        sig do
          params(
            original_contents: T::Hash[String, String],
            updated_contents: T::Hash[String, String],
            names: T::Array[String],
            requested: T::Array[String]
          ).returns(T::Hash[String, String])
        end
        def restore_unrequested(original_contents, updated_contents, names, requested)
          restored = updated_contents.dup
          (names - requested).each do |name|
            previous = original_contents[name]
            next unless previous

            File.write(name, previous) unless restored[name] == previous
            restored[name] = previous
          end
          restored
        end

        sig do
          params(contents: T::Hash[String, String], names: T::Array[String]).returns(T::Hash[String, String])
        end
        def only(contents, names)
          kept = T.let({}, T::Hash[String, String])
          names.each do |name|
            content = contents[name]
            kept[name] = content if content
          end
          kept
        end

        # Whether anything is still owed is asked only of the lockfiles this
        # update is returning. Whether a fallback's output is kept is asked of
        # every lockfile it could have rewritten, which is all of them.
        sig do
          params(
            original_contents: T::Hash[String, String],
            updated_contents: T::Hash[String, String],
            requested: T::Array[String]
          ).returns(T::Hash[String, T::Array[Dependabot::Dependency]])
        end
        def owed_among(original_contents, updated_contents, requested)
          owed_by_unmoved_lockfiles(only(original_contents, requested), only(updated_contents, requested))
        end

        # The same map keyed the other way: each owed dependency, with the
        # lockfiles that owe it.
        sig do
          params(owed: T::Hash[String, T::Array[Dependabot::Dependency]])
            .returns(T::Array[[Dependabot::Dependency, T::Array[String]]])
        end
        def owed_by_dependency(owed)
          dependencies_by_name = T.let({}, T::Hash[String, Dependabot::Dependency])
          lockfiles_by_name = T.let({}, T::Hash[String, T::Array[String]])
          owed.each do |lockfile_name, owed_dependencies|
            owed_dependencies.each do |dep|
              dependencies_by_name[dep.name] ||= dep
              (lockfiles_by_name[dep.name] ||= []) << lockfile_name
            end
          end
          lockfiles_by_name.map { |name, lockfile_names| [T.must(dependencies_by_name[name]), lockfile_names] }
        end

        sig do
          params(
            original_contents: T::Hash[String, String],
            updated_contents: T::Hash[String, String]
          ).returns(T::Hash[String, T::Array[Dependabot::Dependency]])
        end
        def owed_by_unmoved_lockfiles(original_contents, updated_contents)
          owed = T.let({}, T::Hash[String, T::Array[Dependabot::Dependency]])
          original_contents.each do |name, content|
            next unless updated_contents[name] == content

            short = dependencies_short_of_requested_version(content)
            owed[name] = short if short.any?
          end
          owed
        end

        # A fallback resolves the whole workspace, so it can rewrite a project the
        # update had already settled, onto whatever a version-less resolution picks.
        # Only the projects that still owed something take its output; the rest keep
        # what the pinned pass produced, on disk as well as in the result, so the
        # next pass reads the tree this one returns.
        sig do
          params(
            before: T::Hash[String, String],
            names: T::Array[String],
            owed_names: T::Array[String]
          ).returns(T::Hash[String, String])
        end
        def adopt_fallback_output(before, names, owed_names)
          adopted = T.let({}, T::Hash[String, String])
          read_lockfiles(names).each do |name, content|
            if owed_names.include?(name)
              adopted[name] = content
              next
            end

            previous = T.must(before[name])
            File.write(name, previous) unless previous == content
            adopted[name] = previous
          end
          adopted
        end

        sig { params(content: String).returns(T::Array[Dependabot::Dependency]) }
        def dependencies_short_of_requested_version(content)
          candidates = dependencies.select { |dep| mentions_package?(content, dep.name) }
          return [] if candidates.empty?

          resolutions = pnpm_resolutions(content)
          candidates.select do |dep|
            resolved = resolutions.versions(dep.name)
            resolved.empty? || resolved.any? { |version| version != dep.version }
          end
        end

        sig { params(content: String, name: String).returns(T::Boolean) }
        def mentions_package?(content, name)
          content.match?(%r{(?:^|[\s"':])/?#{Regexp.escape(name)}(?:[@:"'\s]|$)})
        end

        sig { params(content: String).returns(NpmAndYarn::PnpmResolutions) }
        def pnpm_resolutions(content)
          cache = (@pnpm_resolutions ||= T.let({}, T.nilable(T::Hash[String, NpmAndYarn::PnpmResolutions])))
          cache[content] ||= PnpmResolutions.new(content)
        end

        sig { params(names: T::Array[String]).returns(T::Hash[String, String]) }
        def read_lockfiles(names)
          names.to_h { |name| [name, File.read(name)] }
        end

        sig { returns(String) }
        def workspace_npmrc_content
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files,
            dependencies: workspace_dependencies
          ).npmrc_content
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def workspace_dependencies
          workspace_pnpm_locks
            .flat_map { |lock| lockfile_dependencies(lock) }
            .uniq { |dep| [dep.name, dep.requirements.map { |requirement| requirement[:source] }] }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def workspace_pnpm_locks
          dependency_files.select { |file| file.name.end_with?(PNPMPackageManager::LOCKFILE_NAME) }
        end

        sig { returns(T.nilable(String)) }
        def run_pnpm_update_packages
          run_pnpm_update_specs(dependencies.map { |d| "#{d.name}@#{d.version}" })
        rescue SharedHelpers::HelperSubprocessFailed => e
          indirect = Helpers.pnpm_indirect_dependency_names(e.message)
          raise if indirect.empty?

          # pnpm 11.23+ refuses to pin a package no manifest declares. Older pnpm
          # ignored the version for such packages, so drop it and let pnpm resolve
          # them as a fresh install would, which is what happened before.
          Dependabot.logger.info(
            "pnpm refused to pin #{indirect.join(', ')} because they are not direct dependencies; " \
            "retrying the update without a version for them"
          )
          @unpinned_dependency_names = indirect
          run_pnpm_update_specs(
            dependencies.map { |d| indirect.include?(d.name) ? d.name : "#{d.name}@#{d.version}" }
          )
        end

        # A workspace that declares a lockfile per project but has never been
        # installed that way still records every member in the lockfile at its
        # root. pnpm honours the declaration on the first install: it reduces that
        # file to the root project alone and writes each member a lockfile of its
        # own. Those files did not exist when the job fetched, so they are not
        # ours to return, and shipping only the reduction deletes every member's
        # resolution while putting nothing in its place — a pull request that
        # cannot install. Measured on pnpm 10.34.5.
        #
        # Only a project that still exists and has nowhere else to go counts.
        # pnpm also drops an importer once the project behind it is gone, and
        # that reduction is pnpm tidying up rather than resolution being lost:
        # reading it as loss would refuse every update a repository in that
        # state ever gets, and tell it to commit a lockfile for a directory it
        # does not have. A project that kept a lockfile of its own is not losing
        # anything either, whether or not this job fetched that lockfile.
        sig do
          params(
            original_contents: T::Hash[String, String],
            updated_contents: T::Hash[String, String]
          ).void
        end
        def verify_importers_retained!(original_contents, updated_contents)
          original_contents.each do |name, original|
            updated = updated_contents[name]
            next unless updated

            orphaned = orphaned_importers(name, original, updated)
            next if orphaned.empty?

            raise Dependabot::DependencyFileNotResolvable,
                  "Updating #{name} dropped #{orphaned.join(', ')}, which no lockfile in this " \
                  "repository records. pnpm keeps a lockfile per project where " \
                  "`sharedWorkspaceLockfile` is disabled; commit one for each of those projects so " \
                  "an update has somewhere to write their dependencies."
          end
        end

        # Projects this lockfile stopped recording that have nowhere else to go:
        # still part of the workspace, and holding no lockfile of their own.
        sig do
          params(name: String, original: String, updated: String).returns(T::Array[String])
        end
        def orphaned_importers(name, original, updated)
          before = importers_in(original)
          after = importers_in(updated)
          return [] unless before && after

          carried = carrying_lockfile_dirs
          root = File.dirname(name)

          (before - after)
            .map { |importer| importer_path(root, importer) }
            .select { |path| project_on_disk?(path) }
            .reject { |path| carried.include?(File.expand_path(path)) }
        end

        # The directories a lockfile sits in, asked of the tree as well as of the
        # fetched files. Existence is already read off the tree, and asking only
        # the fetched files what carries a project reads a member withheld by
        # `exclude_paths` as having nowhere to go — refusing the update, and
        # telling the repository to commit a lockfile that is already there.
        # Generated lockfiles are gone by now, so what is left was committed.
        sig { returns(T::Array[String]) }
        def carrying_lockfile_dirs
          (workspace_pnpm_locks.map(&:name) + lockfile_paths)
            .map { |name| File.expand_path(File.dirname(name)) }
        end

        # The importers a lockfile records, or nil where it cannot be parsed.
        #
        # Both sides have to be readable for the comparison to mean anything: a
        # side read as empty because it would not parse makes every importer look
        # dropped, which would refuse an update over a file this check simply
        # could not read. Skip it instead and leave the parse failure to be
        # reported where it can be explained.
        sig { params(content: String).returns(T.nilable(T::Array[String])) }
        def importers_in(content)
          pnpm_resolutions(content).importers
        rescue Psych::SyntaxError
          nil
        end

        # Whether a project is still part of the workspace, asked of the tree
        # rather than of the fetched files. A member withheld by `exclude_paths` is
        # absent from the dependency files but present on disk, and an importer
        # dropped for it is resolution lost rather than pnpm tidying up after a
        # project that is gone.
        sig { params(path: String).returns(T::Boolean) }
        def project_on_disk?(path)
          File.exist?(File.join(path, MANIFEST_FILENAME))
        end

        # An importer is named relative to the lockfile that records it.
        sig { params(root: String, importer: String).returns(String) }
        def importer_path(root, importer)
          return root if importer == "."
          return importer if root == "."

          File.join(root, importer)
        end

        # An update retried without a version resolves whatever a fresh install
        # would, at every depth, which can differ from the version Dependabot
        # selected under its ignore and cooldown rules. A dependent whose range
        # cannot reach the requested version keeps a lower one, which bypasses
        # nothing. Refuse the batch unless it holds the requested version and no
        # edge the update moved sits above it, rather than open a pull request
        # that names one version and installs another. The question is asked of
        # the batch rather than of each lockfile, since a project that does not
        # carry the dependency at all has nothing to answer with.
        sig do
          params(
            original_contents: T::Hash[String, String],
            updated_contents: T::Hash[String, String]
          ).void
        end
        def verify_unpinned_updates!(original_contents, updated_contents)
          unpinned = @unpinned_dependency_names
          return if unpinned.empty?
          return if original_contents.all? { |name, content| updated_contents[name] == content }

          dependencies.select { |d| unpinned.include?(d.name) }.each do |dep|
            verify_unpinned_dependency!(dep, original_contents, updated_contents)
          end
        end

        sig do
          params(
            dep: Dependabot::Dependency,
            original_contents: T::Hash[String, String],
            updated_contents: T::Hash[String, String]
          ).void
        end
        def verify_unpinned_dependency!(dep, original_contents, updated_contents)
          requested = Version.new(dep.version)
          changed = changed_versions_across(dep.name, original_contents, updated_contents)
          above = changed.reject { |v| Version.correct?(v) && Version.new(v) <= requested }
          versions = updated_contents.values.flat_map { |c| pnpm_resolutions(c).versions(dep.name) }.uniq
          return if above.empty? && versions.include?(dep.version)

          resolved = changed.empty? ? versions : changed
          outcome = if !above.empty?
                      "to #{above.join(', ')}, above the requested #{dep.version}"
                    elsif resolved.empty?
                      "to nothing, rather than to the requested #{dep.version}"
                    else
                      "to #{resolved.join(', ')} instead of the requested #{dep.version}"
                    end
          raise Dependabot::DependencyFileNotResolvable,
                "pnpm resolved #{dep.name} #{outcome}. It is not a direct dependency, so pnpm " \
                "updates it to what a fresh install would resolve rather than to the requested version."
        end

        sig do
          params(
            name: String,
            original_contents: T::Hash[String, String],
            updated_contents: T::Hash[String, String]
          ).returns(T::Array[String])
        end
        def changed_versions_across(name, original_contents, updated_contents)
          original_contents.flat_map do |lockfile_name, original_content|
            updated_content = T.must(updated_contents[lockfile_name])
            next [] if updated_content == original_content

            PnpmResolutions.changed_versions(original_content, updated_content, name)
          end.uniq
        end

        sig { params(specs: T::Array[String]).returns(T.nilable(String)) }
        def run_pnpm_update_specs(specs)
          cmd = "update #{specs.join(' ')}  --lockfile-only --no-save -r"
          fingerprint = "update <dependency_updates>  --lockfile-only --no-save -r"
          run_pnpm_command_with_release_age_gate(cmd, fingerprint)
        end

        sig { returns(T.nilable(String)) }
        def run_pnpm_install
          # `install --lockfile-only` has no dynamic content, so it needs no
          # fingerprint of its own. Passing nil lets the release-age gate handle
          # fingerprinting only when it appends the (dynamic) minimumReleaseAge.
          run_pnpm_command_with_release_age_gate("install --lockfile-only")
        end

        # Failures that mean the cooldown gate cannot be applied to this repo,
        # rather than that the update is wrong. Each is retried once without the
        # gate so a transitive-cooldown preference never blocks the update.
        #
        # The release-age violation is matched on pnpm's lockfile-verification
        # wording rather than the bare error code, because pnpm raises the same
        # code when a *newly resolved* version is too young. Retrying ungated
        # there would admit the very release the cooldown exists to reject, so
        # only the verification pass over entries already in the lockfile — which
        # Dependabot neither introduced nor can fix — is treated as inapplicable.
        RELEASE_AGE_GATE_INAPPLICABLE = T.let(
          {
            /ERR_PNPM_MISSING_TIME/ =>
              "the registry metadata is missing the \"time\" field",
            /ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION[\s\S]*lockfile entries failed verification/ =>
              "the existing lockfile contains entries published inside the cooldown window"
          }.freeze,
          T::Hash[Regexp, String]
        )

        # Security bypass (`=0`) never triggers these, because it disables the age
        # lookup entirely, so it is always re-raised.
        sig { params(cmd: String, fingerprint: T.nilable(String)).returns(T.nilable(String)) }
        def run_pnpm_command_with_release_age_gate(cmd, fingerprint = nil)
          gate = release_age_gate_config
          return run_pnpm_command_under_user_gate(cmd, fingerprint) unless gate

          gate_fingerprint = security_updates_only? ? gate : gate.sub(/(?<=minimum-release-age=)\d+/, "<minutes>")
          gated_fingerprint = "#{fingerprint || cmd} #{gate_fingerprint}"
          begin
            execute_pnpm_command("#{cmd} #{gate}", gated_fingerprint)
          rescue SharedHelpers::HelperSubprocessFailed => e
            raise if security_updates_only?

            _, reason = RELEASE_AGE_GATE_INAPPLICABLE.find { |matcher, _| e.message.match?(matcher) }
            raise unless reason

            Dependabot.logger.warn(
              "pnpm could not apply the cooldown release-age gate because #{reason}; " \
              "retrying without Dependabot's release-age override so the update is not blocked. " \
              "#{fallback_release_age_description(cmd)}"
            )
            # Only the age override is dropped. The repo's own gate applies again,
            # so the command still needs what that gate needs (strict off for
            # `--no-save`), or the retry fails where the first attempt did not.
            run_pnpm_command_under_user_gate(cmd, fingerprint)
          end
        end

        # What still gates transitive dependencies once Dependabot's override is
        # dropped, so the warning does not imply the retry is ungated.
        sig { params(cmd: String).returns(String) }
        def fallback_release_age_description(cmd)
          configured = pnpm_configured_minimum_release_age
          return "pnpm falls back to its own minimumReleaseAge default." if configured.nil?

          description = "pnpm falls back to the repo's own minimumReleaseAge (#{configured} minutes)"
          return "#{description}." unless strict_release_age_off_for_no_save?(cmd)

          "#{description}, with strict mode kept off because pnpm refuses to combine it with --no-save."
        end

        # Runs `cmd` with no Dependabot age override, so the repo's own
        # `minimumReleaseAge` (if any) is the gate. That window is left as the user
        # wrote it; only the two things that would stop every update are adjusted.
        sig { params(cmd: String, fingerprint: T.nilable(String)).returns(T.nilable(String)) }
        def run_pnpm_command_under_user_gate(cmd, fingerprint)
          args = user_release_age_gate_args(cmd)
          return execute_pnpm_command(cmd, fingerprint) unless args

          execute_pnpm_command("#{cmd} #{args}", "#{fingerprint || cmd} #{args}")
        end

        # - Strict mode is turned off, but only for the `--no-save` update: since
        #   pnpm 12.3 an explicit `minimumReleaseAge` makes the gate strict by
        #   default, and strict mode refuses `--no-save` outright
        #   (ERR_PNPM_STRICT_MIN_RELEASE_AGE_REQUIRES_SAVE). Older pnpm refuses once
        #   a resolved version is inside the window. `install` and `audit` have no
        #   such conflict and keep whatever strictness the repo configured.
        # - The existing lockfile is trusted under the same rule as for the cooldown
        #   override (see `trust_existing_lockfile?`), so an entry a human committed
        #   inside the repo's window does not fail every command.
        sig { params(cmd: String).returns(T.nilable(String)) }
        def user_release_age_gate_args(cmd)
          return nil if pnpm_configured_minimum_release_age.nil?

          args = []
          args << STRICT_RELEASE_AGE_OFF if strict_release_age_off_for_no_save?(cmd)
          args << TRUST_LOCKFILE_ON if trust_existing_lockfile?
          args.empty? ? nil : args.join(" ")
        end

        sig { params(cmd: String).returns(T::Boolean) }
        def strict_release_age_off_for_no_save?(cmd)
          return false unless cmd.include?("--no-save")
          return false if pnpm_configured_minimum_release_age.nil?
          return false unless pnpm_supports_minimum_release_age_strict?

          log_strict_release_age_override
          true
        end

        # A repo that sets `minimumReleaseAgeStrict: true` chose it deliberately, so
        # say once why it does not hold for Dependabot's commands.
        sig { void }
        def log_strict_release_age_override
          return if @strict_release_age_override_logged

          @strict_release_age_override_logged = T.let(true, T.nilable(T::Boolean))
          return unless repo_enables_strict_release_age?

          Dependabot.logger.info(
            "pnpm-workspace.yaml sets minimumReleaseAgeStrict: true, but strict mode needs an interactive " \
            "approval that pnpm refuses to combine with the `--no-save` update Dependabot runs, so " \
            "Dependabot passes minimum-release-age-strict=false for its release-age handling. " \
            "The minimumReleaseAge window itself still applies."
          )
        end

        sig { returns(T::Boolean) }
        def repo_enables_strict_release_age?
          dependency_files.any? do |file|
            File.basename(file.name) == "pnpm-workspace.yaml" &&
              yaml_boolean_setting(file.content.to_s, "minimumReleaseAgeStrict", ":") == true
          end
        end

        sig { params(cmd: String, fingerprint: T.nilable(String)).returns(T.nilable(String)) }
        def execute_pnpm_command(cmd, fingerprint)
          if fingerprint
            Helpers.run_pnpm_command(cmd, fingerprint: fingerprint)
          else
            Helpers.run_pnpm_command(cmd)
          end
        end

        # Returns the pnpm `--config.minimum-release-age` arguments to apply, or nil.
        # Security updates disable the gate (`=0`); regular updates apply the
        # dependabot.yml cooldown floor (in minutes). `minimumReleaseAge` was added
        # in pnpm 10.16, so older pnpm silently ignores it — rather than give a
        # false guarantee we skip the gate (and warn) when the running pnpm is too
        # old to enforce it.
        sig { returns(T.nilable(String)) }
        def release_age_gate_config
          if !security_updates_only? && @release_age_days&.positive? && !pnpm_supports_minimum_release_age?
            Dependabot.logger.warn(
              "pnpm #{pnpm_version || '(unknown version)'} does not support minimumReleaseAge " \
              "(added in pnpm 10.16); the release-age cooldown cannot be enforced for transitive " \
              "dependencies on this pnpm version."
            )
            return nil
          end

          minutes = effective_release_age_minutes
          return nil if minutes.nil?

          # Security updates pass minimumReleaseAge=0 unconditionally: older pnpm
          # ignores it, and a transient version-probe failure must not leave a native
          # gate active and block the fix.
          return minimum_release_age_gate_args(minutes) if security_updates_only?

          minimum_release_age_gate_args(minutes)
        end

        # The pnpm `minimumReleaseAge` value (in minutes) to enforce for this
        # update, independent of the pnpm version: 0 to bypass the gate for
        # security fixes (which must not be blocked by a release-age gate the user
        # configured for regular updates), the dependabot.yml cooldown floor for
        # regular updates, or nil when no gate applies.
        #
        # When the repo also sets an explicit `minimumReleaseAge` in
        # pnpm-workspace.yaml (or `.npmrc`), the longest release-age wins: the
        # cooldown floor is only injected when it exceeds the user's configured
        # value, otherwise the user's (equal or longer) gate is left untouched so
        # neither policy is silently weakened (dependabot/dependabot-core#13165).
        sig { returns(T.nilable(Integer)) }
        def effective_release_age_minutes
          return 0 if security_updates_only?

          cooldown_minutes = @release_age_days && (@release_age_days * Helpers::MINUTES_PER_DAY)
          Helpers.higher_release_age_gate(cooldown_minutes, pnpm_configured_minimum_release_age)
        end

        # Builds the pnpm `--config.minimum-release-age` args for `minutes`, adding
        # the strict toggle only when appropriate (see `disable_strict_release_age?`)
        # and trusting the existing lockfile where that is safe (see
        # `trust_existing_lockfile?`).
        sig { params(minutes: Integer).returns(String) }
        def minimum_release_age_gate_args(minutes)
          args = "--config.minimum-release-age=#{minutes}"
          if disable_strict_release_age?
            log_strict_release_age_override unless security_updates_only?
            args += " #{STRICT_RELEASE_AGE_OFF}"
          end
          args += " #{TRUST_LOCKFILE_ON}" if trust_existing_lockfile?
          args
        end

        # pnpm re-applies the gate to every entry already in the lockfile, so a
        # version a human committed inside the cooldown window fails the whole
        # command even though Dependabot neither introduced it nor can fix it
        # (dependabot/dependabot-core#15937). Trusting the lockfile keeps the
        # cooldown enforced for the versions pnpm resolves now, rather than dropping
        # it wholesale, so an update is still delivered under the gate.
        #
        # It is skipped when the repo states its own lockfile-verification policy:
        # `trustLockfile` is the user's to set, and `trustPolicy` re-verification of
        # loaded entries is an independent supply-chain control that this must not
        # silently disable. Those repos fall back to the ungated retry.
        #
        # Memoized so the decision is logged once per update, not per command.
        sig { returns(T::Boolean) }
        def trust_existing_lockfile?
          @trust_existing_lockfile = compute_trust_existing_lockfile? if @trust_existing_lockfile.nil?
          @trust_existing_lockfile
        end

        sig { returns(T::Boolean) }
        def compute_trust_existing_lockfile?
          return false if security_updates_only?
          return false unless pnpm_supports_trust_lockfile?

          configured = configured_lockfile_verification_settings
          unless configured.empty?
            Dependabot.logger.info(
              "pnpm-workspace.yaml sets #{configured.join(', ')}, so Dependabot will not pass " \
              "trustLockfile; entries already in the lockfile are still verified against the " \
              "cooldown window, and a violation there falls back to an ungated retry."
            )
            return false
          end

          true
        end

        # pnpm defaults `minimumReleaseAgeStrict` to *on* when `minimumReleaseAge`
        # is set via the CLI, which fails resolution when no version satisfies the
        # window and is incompatible with the `--no-save` update command. We
        # disable strict for Dependabot's CLI override on pnpm >= 11.0, where the
        # toggle exists. Equal-or-longer native gates get no age override; see
        # `user_release_age_gate_args` for what they do get.
        sig { returns(T::Boolean) }
        def disable_strict_release_age?
          pnpm_supports_minimum_release_age_strict?
        end

        # The concrete pnpm version that will run, memoized (including a nil result)
        # so the version subprocess runs at most once per update.
        sig { returns(T.nilable(Dependabot::Version)) }
        def pnpm_version
          return @pnpm_version if defined?(@pnpm_version)

          @pnpm_version = T.let(Helpers.pnpm_version, T.nilable(Dependabot::Version))
        end

        sig { returns(T::Boolean) }
        def pnpm_supports_minimum_release_age?
          version = pnpm_version
          return false if version.nil? || version < Version.new(PNPM_MINIMUM_RELEASE_AGE_VERSION)

          if pnpm_shared_workspace_lockfile_disabled? &&
             version < Version.new(PNPM_WORKSPACE_RELEASE_AGE_FIX_VERSION)
            Dependabot.logger.warn(
              "pnpm #{version} ignores minimumReleaseAge when shared-workspace-lockfile is disabled " \
              "(pnpm/pnpm#10008); the release-age cooldown cannot be enforced. Upgrade to pnpm 11+."
            )
            return false
          end

          true
        end

        sig { returns(T::Boolean) }
        def pnpm_supports_minimum_release_age_strict?
          version = pnpm_version
          !version.nil? && version >= Version.new(PNPM_MINIMUM_RELEASE_AGE_STRICT_VERSION)
        end

        sig { returns(T::Boolean) }
        def pnpm_supports_trust_lockfile?
          version = pnpm_version
          !version.nil? && version >= Version.new(PNPM_TRUST_LOCKFILE_VERSION)
        end

        # The lockfile-verification settings the repo states for itself, via
        # pnpm-workspace.yaml. Named rather than boolean so the log can say which
        # setting held `trustLockfile` back.
        sig { returns(T::Array[String]) }
        def configured_lockfile_verification_settings
          dependency_files.flat_map do |file|
            next [] unless File.basename(file.name) == "pnpm-workspace.yaml"

            workspace_setting_names(file.content.to_s) & LOCKFILE_VERIFICATION_SETTINGS
          end.uniq
        end

        # Top-level keys of a pnpm-workspace.yaml. Parsed as YAML rather than
        # matched per line so flow-style mappings (`{ trustPolicy: no-downgrade }`)
        # are seen.
        sig { params(content: String).returns(T::Array[String]) }
        def workspace_setting_names(content)
          parsed = T.cast(YAML.safe_load(content, aliases: true), Object)
          return [] unless parsed.is_a?(Hash)

          parsed.keys.map { |key| T.cast(key, Object).to_s }
        end

        # pnpm 10.x ignores `minimumReleaseAge` when `shared-workspace-lockfile` is
        # disabled (pnpm/pnpm#10008), so the cooldown cannot be enforced there.
        sig { returns(T::Boolean) }
        def pnpm_shared_workspace_lockfile_disabled?
          PnpmWorkspaceConfig.lockfile_per_project?(dependency_files)
        end

        # Reads a boolean setting matched line by line, returning true/false, or
        # nil when absent or non-boolean. Its remaining caller reads
        # `minimumReleaseAgeStrict` out of a pnpm-workspace.yaml; the layout
        # setting moved to `PnpmWorkspaceConfig`, which parses that file instead
        # so a flow-style mapping is not missed. Handles optionally quoted
        # keys/values, boolean casing, and trailing comments. The last occurrence
        # wins, matching how pnpm and INI resolve a repeated key.
        sig { params(content: String, key: String, separator: String).returns(T.nilable(T::Boolean)) }
        def yaml_boolean_setting(content, key, separator)
          quoted_key = /["']?#{Regexp.escape(key)}["']?/
          presence = /^\s*#{quoted_key}\s*#{Regexp.escape(separator)}/
          last_line = content.lines.reverse_each.find { |line| line.match?(presence) }
          return unless last_line

          # npmrc/INI treats both `#` and `;` as comment delimiters; YAML uses `#`.
          comment_chars = separator == "=" ? "#;" : "#"
          match = last_line.match(
            /^\s*#{quoted_key}\s*#{Regexp.escape(separator)}\s*["']?(\w+)["']?\s*(?:[#{comment_chars}].*)?$/
          )
          return unless match

          case T.must(match[1]).downcase
          when "true" then true
          when "false" then false
          end
        end

        # The largest `minimumReleaseAge` (in minutes) the repo configures for pnpm,
        # read from pnpm-workspace.yaml (`minimumReleaseAge:`) or `.npmrc`
        # (`minimum-release-age=`), or nil when unset. A value we cannot parse as a
        # bare integer is reported as Float::INFINITY so an explicit-but-non-numeric
        # user gate is never overridden by the cooldown floor.
        sig { returns(T.nilable(T.any(Integer, Float))) }
        def pnpm_configured_minimum_release_age
          settings = [
            Helpers::ReleaseAgeGateSetting.new(
              filename: "pnpm-workspace.yaml", key: "minimumReleaseAge", separator: ":"
            )
          ]
          # pnpm 11+ ignores non-registry settings in .npmrc, so a .npmrc
          # `minimum-release-age` is only an effective user gate on pnpm 10.x.
          # Counting it on pnpm 11 would wrongly suppress the cooldown CLI override
          # while pnpm resolves with no age gate.
          if pnpm_reads_npmrc_release_age?
            settings << Helpers::ReleaseAgeGateSetting.new(
              filename: ".npmrc", key: "minimum-release-age", separator: "="
            )
          end

          Helpers.max_configured_release_age(dependency_files, settings)
        end

        sig { returns(T::Boolean) }
        def pnpm_reads_npmrc_release_age?
          version = pnpm_version
          !version.nil? && version < Version.new(PNPM_NPMRC_RELEASE_AGE_DROPPED_VERSION)
        end

        # Tries `pnpm update --depth Infinity <dep>` for each dependency as a
        # first-tier fallback when the regular update is a no-op (typically
        # transitive deps not listed in any package.json), without relying on
        # audit fixes that may modify manifests on older pnpm versions. It is
        # routed through the release-age gate so the fallback cannot bypass the
        # transitive dependency cooldown.
        sig { params(deps: T::Array[Dependabot::Dependency]).void }
        def run_pnpm_deep_update_fallback(deps)
          recursive = workspace_files.any?
          deps.each do |dep|
            cmd, fingerprint = NativeHelpers.pnpm_deep_update_command(dep.name, recursive: recursive)
            run_pnpm_command_with_release_age_gate(cmd, fingerprint)
            dep.metadata[:deep_update_used] = true
          end
        rescue SharedHelpers::HelperSubprocessFailed
          Dependabot.logger.info(
            "pnpm update --depth Infinity failed or partially fixed — continuing with any changes made"
          )
        end

        # Runs the version-compatible `pnpm audit --fix` strategy when the primary update is a no-op.
        # pnpm 11 updates the lockfile directly, while older versions may add
        # `overrides` to package.json. Since only lockfile content can be returned,
        # revert any manifest and lockfile changes so the operation remains consistent.
        sig { params(snapshot_contents: T::Hash[String, String]).void }
        def run_pnpm_audit_fix_fallback(snapshot_contents)
          package_json_snapshots = Dir.glob("**/package.json").to_h { |f| [f, File.read(f)] }
          # Taken off the tree rather than from the fetched set, which does not cover
          # every lockfile the audit can reach: a member's own lockfile that this job
          # never fetched is rewritten all the same. Restoring only what was fetched
          # would leave such a file at the audit result while everything around it
          # went back.
          lockfile_snapshots = Dir.glob("**/#{PNPMPackageManager::LOCKFILE_NAME}").to_h { |f| [f, File.read(f)] }

          begin
            cmd, fingerprint = NativeHelpers.pnpm_audit_fix_command
            run_pnpm_command_with_release_age_gate(cmd, fingerprint)
            run_pnpm_install

            if package_json_snapshots.any? { |f, c| File.read(f) != c }
              revert_audit_fix(package_json_snapshots, lockfile_snapshots, snapshot_contents)
            else
              dependencies.each { |dep| dep.metadata[:audit_fix_used] = true }
            end
          rescue SharedHelpers::HelperSubprocessFailed
            Dependabot.logger.info(
              "pnpm audit --fix failed or partially fixed — continuing with any changes made"
            )
          end
        end

        # Everything the audit touched goes back: the manifests, every lockfile on
        # the tree — including one the primary install created — and the fetched
        # lockfiles, which may sit above the job directory and so outside the glob.
        sig do
          params(
            manifests: T::Hash[String, String],
            lockfiles: T::Hash[String, String],
            fetched: T::Hash[String, String]
          ).void
        end
        def revert_audit_fix(manifests, lockfiles, fetched)
          Dependabot.logger.info(
            "pnpm audit --fix modified package.json (overrides) — reverting fallback"
          )
          manifests.each { |name, content| File.write(name, content) }
          lockfiles.each { |name, content| File.write(name, content) }
          fetched.each { |name, content| File.write(name, content) }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def workspace_files
          @workspace_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?("pnpm-workspace.yaml") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { params(lockfile: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
        def lockfile_dependencies(lockfile)
          @lockfile_dependencies ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependabot::Dependency]]))
          @lockfile_dependencies[lockfile.name] ||=
            NpmAndYarn::FileParser.new(
              dependency_files: [lockfile, *manifests_describing(lockfile), *workspace_files],
              source: nil,
              credentials: credentials
            ).parse
        end

        # A lockfile beside a project describes that project alone, so parsing it
        # against every manifest in the workspace invents a copy of each other
        # project's dependencies with no resolution behind it — source-less, and
        # distinguishable from the copy that knows its registry only by that
        # absence. Pair each lockfile with the manifests it actually describes.
        # Where one lockfile is shared it describes them all, and that is the
        # layout the fetcher leaves with no member lockfile at all, so nothing
        # changes there.
        sig { params(lockfile: Dependabot::DependencyFile).returns(T::Array[Dependabot::DependencyFile]) }
        def manifests_describing(lockfile)
          members = workspace_pnpm_locks.reject { |lock| File.dirname(lock.name) == "." }
          return package_files if members.empty?

          directory = File.dirname(lockfile.name)
          owned = package_files.select { |file| File.dirname(file.name) == directory }
          return package_files if owned.empty?
          # The parser wants the manifest at the root whatever it is parsing.
          return (root_package_files + owned).uniq unless directory == "."

          # The root lockfile covers the root project, and any project that kept
          # no lockfile of its own.
          covered = members.map { |lock| File.dirname(lock.name) }
          owned + package_files.reject do |file|
            dir = File.dirname(file.name)
            dir == "." || covered.include?(dir)
          end
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def root_package_files
          package_files.select { |file| File.dirname(file.name) == "." }
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/CyclomaticComplexity
        sig do
          params(
            error: SharedHelpers::HelperSubprocessFailed,
            pnpm_locks: T::Array[Dependabot::DependencyFile]
          )
            .returns(T.noreturn)
        end
        def handle_pnpm_lock_updater_error(error, pnpm_locks)
          error_message = error.message

          if error_message.include?(IRRESOLVABLE_PACKAGE) || error_message.include?(INVALID_REQUIREMENT)
            raise_resolvability_error(error_message, pnpm_locks)
          end

          if error_message.match?(UNREACHABLE_GIT)
            url = error_message.match(UNREACHABLE_GIT)&.named_captures&.fetch("url")&.gsub("git+ssh://git@", "https://")&.delete_suffix(".git")

            raise Dependabot::GitDependenciesNotReachable, T.must(url)
          end

          if error_message.match?(UNREACHABLE_GIT_V8)
            url = error_message.match(UNREACHABLE_GIT_V8)&.named_captures&.fetch("url")&.gsub("codeload.", "")

            raise Dependabot::GitDependenciesNotReachable, T.must(url)
          end

          [FORBIDDEN_PACKAGE, MISSING_PACKAGE, UNAUTHORIZED_PACKAGE, ERR_PNPM_FETCH_401,
           ERR_PNPM_FETCH_403, ERR_PNPM_FETCH_404, ERR_PNPM_FETCH_500, ERR_PNPM_FETCH_502, ERR_PNPM_FETCH_503]
            .each do |regexp|
            next unless error_message.match?(regexp)

            dependency_url = T.must(error_message.match(regexp)&.named_captures&.[]("dependency_url"))
            raise_package_access_error(error_message, dependency_url)
          end

          # TO-DO : subclassifcation of ERR_PNPM_TARBALL_INTEGRITY errors
          if error_message.match?(ERR_PNPM_TARBALL_INTEGRITY)
            dependency_names = dependencies.map(&:name).join(", ")
            msg = "Error (ERR_PNPM_TARBALL_INTEGRITY) while resolving \"#{dependency_names}\"."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          # TO-DO : investigate "packageManager" allowed regex
          if error_message.match?(INVALID_PACKAGE_SPEC)
            dependency_names = dependencies.map(&:name).join(", ")
            msg = "Invalid package manager specification in package.json while resolving \"#{dependency_names}\"."
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_META_FETCH_FAIL)
            msg = error_message.split(ERR_PNPM_META_FETCH_FAIL).last
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_WORKSPACE_PKG_NOT_FOUND)
            dependency_names = dependencies.map(&:name).join(", ")
            msg = "No package named \"#{dependency_names}\" present in workspace."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_BROKEN_METADATA_JSON)
            msg = "Error (ERR_PNPM_BROKEN_METADATA_JSON) while resolving \"pnpm-lock.yaml\" file."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND)
            dir = error_message.match(ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND)&.named_captures&.fetch("dir")
            msg = "Could not find linked package installation directory \"#{dir&.split('/')&.last}\""
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_INVALID_PACKAGE_JSON) || error_message.match?(ERR_PNPM_UNEXPECTED_STORE)
            msg = "Error while resolving package.json."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if (match = error_message.match(ERR_PNPM_INVALID_DEPENDENCY_NAME))
            invalid_dep = match.named_captures["dep"]
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyNotFound, T.must(invalid_dep)
          end

          [ERR_PNPM_UNEXPECTED_PKG_CONTENT_IN_STORE, ERR_PNPM_OUTDATED_LOCKFILE]
            .each do |regexp|
            next unless error_message.match?(regexp)

            error_msg = T.let("Error while resolving pnpm-lock.yaml file.", String)

            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, error_msg
          end

          if error_message.match?(ERR_PNPM_PEER_DEP_ISSUES)
            msg = "Missing or invalid configuration while installing peer dependencies."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          raise_patch_dependency_error(error_message) if error_message.match?(ERR_PNPM_PATCH_NOT_APPLIED)
          raise_unsupported_engine_error(error_message, pnpm_locks) if error_message.match?(ERR_PNPM_UNSUPPORTED_ENGINE)

          if error_message.match?(ERR_INVALID_THIS) && error_message.match?(URL_SEARCH_PARAMS)
            msg = "Error while resolving dependencies."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_UNSUPPORTED_PLATFORM)
            raise_unsupported_platform_error(error_message, pnpm_locks)
          end

          if error_message.match?(ERR_PNPM_TRUST_DOWNGRADE)
            dep = error_message.match(TRUST_DOWNGRADE_PACKAGE)&.named_captures&.fetch("dep", nil)
            dep_info = dep ? " for \"#{dep}\"" : ""
            msg = "pnpm trust downgrade detected#{dep_info}. " \
                  "A previously published version had provenance attestation, but the target version does not."
            Dependabot.logger.warn(error_message)
            raise Dependabot::InconsistentRegistryResponse, msg
          end

          error_handler.handle_pnpm_error(error)

          raise
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/CyclomaticComplexity

        sig { params(error_message: String, pnpm_locks: T::Array[Dependabot::DependencyFile]).returns(T.noreturn) }
        def raise_resolvability_error(error_message, pnpm_locks)
          dependency_names = dependencies.map(&:name).join(", ")
          paths = pnpm_locks.map(&:path).join(", ")
          msg = "Error whilst updating #{dependency_names} in " \
                "#{paths}:\n#{error_message}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        sig { params(error_message: String).returns(T.noreturn) }
        def raise_patch_dependency_error(error_message)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error while updating \"#{dependency_names}\" in " \
                "update group \"patchedDependencies\"."
          Dependabot.logger.warn(error_message)
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        sig do
          params(
            error_message: String,
            _pnpm_locks: T::Array[Dependabot::DependencyFile]
          ).returns(T.nilable(T.noreturn))
        end
        def raise_unsupported_engine_error(error_message, _pnpm_locks)
          match_pkg_mgr = error_message.match(PACAKGE_MANAGER)
          match_version = error_message.match(VERSION_REQUIREMENT)

          unless match_pkg_mgr && match_version &&
                 match_pkg_mgr.named_captures && match_version.named_captures
            return nil
          end

          captures_pkg_mgr = match_pkg_mgr.named_captures
          captures_version = match_version.named_captures

          pkg_mgr = captures_pkg_mgr["pkg_mgr"]
          supported_ver = captures_version["supported_ver"]
          detected_ver = captures_version["detected_ver"]

          if pkg_mgr && supported_ver && detected_ver
            raise Dependabot::ToolVersionNotSupported.new(
              pkg_mgr,
              supported_ver,
              detected_ver
            )
          end

          nil
        end

        sig do
          params(
            error_message: String,
            dependency_url: String
          )
            .returns(T.noreturn)
        end
        def raise_package_access_error(error_message, dependency_url)
          package_name = RegistryParser.new(
            resolved_url: dependency_url,
            credentials: credentials
          ).dependency_name
          named = workspace_dependencies.select { |dep| dep.name == package_name }
          missing_dep = named.find { |dep| dep.requirements.any? { |r| r[:source] } } || named.first
          raise DependencyNotFound, package_name unless missing_dep

          reg = Package::RegistryFinder.new(
            dependency: missing_dep,
            credentials: credentials,
            npmrc_file: npmrc_file
          ).registry
          Dependabot.logger.warn("Error while accessing #{reg}. Response (truncated) - #{error_message[0..500]}...")
          raise PrivateSourceAuthenticationFailure, reg
        end

        sig { void }
        def write_final_package_json_files
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_package_json_content(file))
          end
        end

        sig do
          params(
            error_message: String,
            _pnpm_locks: T::Array[Dependabot::DependencyFile]
          )
            .returns(T.nilable(T.noreturn))
        end
        def raise_unsupported_platform_error(error_message, _pnpm_locks)
          match_dep = error_message.match(PLATFORM_PACAKGE_DEP)
          match_version = error_message.match(PLATFORM_VERSION_REQUIREMENT)

          unless match_dep && match_version &&
                 match_dep.named_captures && match_version.named_captures
            return nil
          end

          captures_version = match_version.named_captures

          supported_ver = captures_version["supported_ver"]
          detected_ver = captures_version["detected_ver"]

          if supported_ver && detected_ver
            supported_version = sanitize_message(supported_ver)
            detected_version = sanitize_message(detected_ver)

            Dependabot.logger.warn(error_message)
            raise Dependabot::ToolVersionNotSupported.new(
              PLATFORM_PACAKGE_MANAGER,
              supported_version,
              detected_version
            )
          end

          nil
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def updated_package_json_content(file)
          @updated_package_json_content ||= T.let({}, T.nilable(T::Hash[String, String]))
          @updated_package_json_content[file.name] ||=
            T.must(
              PackageJsonUpdater.new(
                package_json: file,
                dependencies: dependencies
              ).updated_package_json.content
            )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_files
          @package_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?("package.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(String) }
        def base_dir
          T.must(dependency_files.first).directory
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def npmrc_file
          dependency_files.find { |f| f.name == ".npmrc" }
        end

        sig { params(message: String).returns(String) }
        def sanitize_message(message)
          message.gsub(/"|\[|\]|\}|\{/, "")
        end
      end
    end
    # rubocop:enable Metrics/ClassLength

    class PnpmErrorHandler
      extend T::Sig

      # remote connection closed
      ECONNRESET_ERROR = /ECONNRESET/

      # socket hang up error code
      SOCKET_HANG_UP = /socket hang up/

      # ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC error
      ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC = /ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC/

      # duplicate package error code
      DUPLICATE_PACKAGE = /Found duplicates/

      ERR_PNPM_NO_VERSIONS = /ERR_PNPM_NO_VERSIONS/

      # Initializes the YarnErrorHandler with dependencies and dependency files
      sig do
        params(
          dependencies: T::Array[Dependabot::Dependency],
          dependency_files: T::Array[Dependabot::DependencyFile]
        )
          .void
      end
      def initialize(dependencies:, dependency_files:)
        @dependencies = dependencies
        @dependency_files = dependency_files
      end

      private

      sig { returns(T::Array[Dependabot::Dependency]) }
      attr_reader :dependencies

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      public

      # Handles errors with specific to yarn error codes
      sig { params(error: SharedHelpers::HelperSubprocessFailed).void }
      def handle_pnpm_error(error)
        if error.message.match?(DUPLICATE_PACKAGE) || error.message.match?(ERR_PNPM_NO_VERSIONS) ||
           error.message.match?(ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC)

          raise DependencyFileNotResolvable, "Error resolving dependency"
        end

        ## Clean error message from ANSI escape codes
        return unless error.message.match?(ECONNRESET_ERROR) || error.message.match?(SOCKET_HANG_UP)

        raise InconsistentRegistryResponse, "Inconsistent registry response while resolving dependency"
      end
    end
  end
end
