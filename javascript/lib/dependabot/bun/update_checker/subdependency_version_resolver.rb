# typed: true
# frozen_string_literal: true

module Dependabot
  module Bun
    class UpdateChecker
      class SubdependencyVersionResolver
        def initialize(dependency:, credentials:, dependency_files:,
                       ignored_versions:, latest_allowable_version:, repo_contents_path:)
          @dependency = dependency
          @credentials = credentials
          @dependency_files = dependency_files
          @ignored_versions = ignored_versions
          @latest_allowable_version = latest_allowable_version
          @repo_contents_path = repo_contents_path
        end

        def latest_resolvable_version
          raise "Not a subdependency!" if dependency.requirements.any?
          return if bundled_dependency?

          base_dir = dependency_files.first.directory
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            dependency_files_builder.write_temporary_dependency_files

            updated_lockfiles = filtered_lockfiles.map do |lockfile|
              updated_content = update_subdependency_in_lockfile(lockfile)
              updated_lockfile = lockfile.dup
              updated_lockfile.content = updated_content
              updated_lockfile
            end

            version_from_updated_lockfiles(updated_lockfiles)
          end
        rescue SharedHelpers::HelperSubprocessFailed
          # TODO: Move error handling logic from the FileUpdater to this class

          # Return nil (no update possible) if an unknown error occurred
          nil
        end

        private

        attr_reader :dependency
        attr_reader :credentials
        attr_reader :dependency_files
        attr_reader :ignored_versions
        attr_reader :latest_allowable_version
        attr_reader :repo_contents_path

        def update_subdependency_in_lockfile(lockfile)
          lockfile_name = Pathname.new(lockfile.name).basename.to_s
          path = Pathname.new(lockfile.name).dirname.to_s

          updated_files = run_bun_updater(path, lockfile_name) if lockfile.name.end_with?("bun.lock")

          updated_files.fetch(lockfile_name)
        end

        def version_from_updated_lockfiles(updated_lockfiles)
          updated_files = dependency_files -
                          dependency_files_builder.lockfiles +
                          updated_lockfiles

          updated_version = NpmAndYarn::FileParser.new(
            dependency_files: updated_files,
            source: nil,
            credentials: credentials
          ).parse.find { |d| d.name == dependency.name }&.version
          return unless updated_version

          version_class.new(updated_version)
        end

        def run_bun_updater(path, lockfile_name)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              Helpers.run_bun_command(
                "update #{dependency.name} --save-text-lockfile",
                fingerprint: "update <dependency_name> --save-text-lockfile"
              )
              { lockfile_name => File.read(lockfile_name) }
            end
          end
        end

        def version_class
          dependency.version_class
        end

        def updated_dependency
          Dependabot::Dependency.new(
            name: dependency.name,
            version: latest_allowable_version,
            previous_version: dependency.version,
            requirements: [],
            package_manager: dependency.package_manager
          )
        end

        def filtered_lockfiles
          @filtered_lockfiles ||=
            Javascript::SubDependencyFilesFilterer.new(
              dependency_files: dependency_files,
              updated_dependencies: [updated_dependency]
            ).files_requiring_update
        end

        def dependency_files_builder
          @dependency_files_builder ||=
            DependencyFilesBuilder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials
            )
        end

        # TODO: We should try and fix this by updating the parent that's not
        # bundled. For this case: `chokidar > fsevents > node-pre-gyp > tar` we
        # would need to update `fsevents`
        #
        # We shouldn't update bundled sub-dependencies as they have been bundled
        # into the release at an exact version by a parent using
        # `bundledDependencies`.
        #
        # For example, fsevents < 2 bundles node-pre-gyp meaning all it's
        # sub-dependencies get bundled into the release tarball at publish time
        # so you always get the same sub-dependency versions if you re-install a
        # specific version of fsevents.
        #
        # Updating the sub-dependency by deleting the entry works but it gets
        # removed from the bundled set of dependencies and moved top level
        # resulting in a bunch of package duplication which is pretty confusing.
        def bundled_dependency?
          dependency.subdependency_metadata
                    &.any? { |h| h.fetch(:npm_bundled, false) } ||
            false
        end
      end
    end
  end
end
