# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/security_advisory"
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

        # `--update-locks` only unlocks a module; Gradle may resolve a vulnerable
        # version again, or move to a different vulnerable one (e.g. a parent
        # still requires it). Every regenerated version must therefore not be
        # affected by the advisories the update was computed from.
        sig do
          params(files: T::Array[Dependabot::DependencyFile], dependencies: T::Array[Dependabot::Dependency]).void
        end
        def verify_versions_changed(files, dependencies)
          dependencies.each do |dependency|
            lockfile_names = dependency.metadata_string_array(:lockfiles).to_a
            resolved = resolved_versions(files.select { |f| lockfile_names.include?(f.name) }, dependency.name)
            unfixed = resolved.reject { |version| acceptable_version?(dependency, version) }
            next if unfixed.empty?

            raise DependencyFileNotResolvable,
                  "#{dependency.name} still resolves to #{unfixed.join(', ')} after unlocking " \
                  "(target #{dependency.version}, resolved: #{resolved.join(', ')}); " \
                  "another dependency may require it"
          end
        end

        sig { params(dependency: Dependabot::Dependency, version: String).returns(T::Boolean) }
        def acceptable_version?(dependency, version)
          return !vulnerable_by_advisories?(dependency, version) if advisories?(dependency)

          vulnerable = dependency.metadata_string_array(:vulnerable_versions) || [dependency.previous_version].compact
          original = dependency.metadata_string_array(:resolved_versions) || []
          return true if (original - vulnerable).include?(version)

          target = dependency.version
          return false unless target && Gradle::Version.correct?(version) && Gradle::Version.correct?(target)

          Gradle::Version.new(version) >= Gradle::Version.new(target)
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def advisories?(dependency)
          !dependency.metadata_array(:advisories).to_a.empty?
        end

        # Validates against the advisories' own ranges, since a version above the
        # target can still be affected when an advisory has disjoint ranges.
        sig { params(dependency: Dependabot::Dependency, version: String).returns(T::Boolean) }
        def vulnerable_by_advisories?(dependency, version)
          return true unless Gradle::Version.correct?(version)

          dependency.metadata_array(:advisories).to_a.any? do |raw|
            advisory = T.cast(raw, T::Hash[Symbol, T::Array[String]])
            Dependabot::SecurityAdvisory.new(
              dependency_name: dependency.name,
              package_manager: "gradle",
              vulnerable_versions: advisory.fetch(:vulnerable).flat_map do |r|
                Gradle::Requirement.requirements_array(r)
              end,
              safe_versions: advisory.fetch(:safe)
            ).vulnerable?(Gradle::Version.new(version))
          end
        end

        sig { params(lockfiles: T::Array[Dependabot::DependencyFile], name: String).returns(T::Array[String]) }
        def resolved_versions(lockfiles, name)
          lockfiles.flat_map do |lockfile|
            T.must(lockfile.content).scan(/^#{Regexp.escape(name)}:([^=\s]+)=/).flatten
          end.uniq
        end
      end
    end
  end
end
