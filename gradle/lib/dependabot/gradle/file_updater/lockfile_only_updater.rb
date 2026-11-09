# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_updater"
require "dependabot/gradle/file_updater/lockfile_updater"

module Dependabot
  module Gradle
    class FileUpdater
      # Regenerates the lockfiles that resolve transitive dependencies, which
      # have no declaration in a build file to edit.
      class LockfileOnlyUpdater
        extend T::Sig

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            repo_contents_path: T.nilable(String)
          ).void
        end
        def initialize(dependency_files:, repo_contents_path:)
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
        end

        sig do
          params(
            files: T::Array[Dependabot::DependencyFile],
            dependencies: T::Array[Dependabot::Dependency]
          ).returns(T::Array[Dependabot::DependencyFile])
        end
        def update(files, dependencies)
          updated = files.dup
          support_files = @dependency_files.select(&:support_file?)
          names = dependencies.map(&:name)

          owners_by_root(updated, dependencies).each_value do |owners|
            # Built per root from the accumulated files so earlier roots' results are kept
            lockfile_updater = LockfileUpdater.new(
              dependency_files: updated + support_files,
              repo_contents_path: @repo_contents_path
            )
            result = lockfile_updater.update_lockfiles(T.must(owners.first), build_files: owners, update_locks: names)
            replace_files(updated, result.reject(&:support_file?))
          end

          verify_versions_changed(updated, dependencies)
          updated
        end

        private

        sig do
          params(
            files: T::Array[Dependabot::DependencyFile],
            dependencies: T::Array[Dependabot::Dependency]
          ).returns(T::Hash[String, T::Array[Dependabot::DependencyFile]])
        end
        def owners_by_root(files, dependencies)
          root_finder = LockfileUpdater.new(dependency_files: files)
          owners = dependencies.flat_map do |dependency|
            found = dependency.metadata_string_array(:owning_buildfiles).to_a.filter_map do |name|
              files.find { |f| f.name == name }
            end
            raise DependencyFileNotResolvable, "No build file found to update the dependency" if found.empty?

            found
          end
          owners.uniq.group_by { |owner| root_finder.determine_root_dir(build_file: owner) }
        end

        sig do
          params(
            files: T::Array[Dependabot::DependencyFile],
            updated_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def replace_files(files, updated_files)
          updated_files.each do |file|
            index = files.find_index { |f| f.name == file.name }
            index ? files[index] = file : files << file
          end
        end

        # `--update-locks` only unlocks a module; Gradle may resolve the same
        # version again (e.g. a parent still requests it), which would leave the
        # vulnerable version in place.
        sig do
          params(files: T::Array[Dependabot::DependencyFile], dependencies: T::Array[Dependabot::Dependency]).void
        end
        def verify_versions_changed(files, dependencies)
          dependencies.each do |dependency|
            previous = dependency.previous_version
            next unless previous

            lockfile_names = dependency.metadata_string_array(:lockfiles).to_a
            stale = files.select { |f| lockfile_names.include?(f.name) }.select do |f|
              T.must(f.content).include?("#{dependency.name}:#{previous}=")
            end
            next if stale.empty?

            raise DependencyFileNotResolvable,
                  "#{dependency.name} still resolves to #{previous} in #{stale.map(&:name).join(', ')} " \
                  "after unlocking; another dependency may require it"
          end
        end
      end
    end
  end
end
