# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/npm_and_yarn/file_updater/npmrc_builder"
require "dependabot/npm_and_yarn/file_updater/package_json_preparer"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class DependencyFilesBuilder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { void }
        def write_temporary_dependency_files
          write_lockfiles

          if Helpers.yarn_berry?(yarn_locks.first)
            if yarnrc_yml_file
              write_dependency_file(
                file: T.must(yarnrc_yml_file),
                content: T.must(yarnrc_yml_content)
              )
            end
          else
            File.write(".npmrc", npmrc_content)
            File.write(".yarnrc", yarnrc_content) if yarnrc_specifies_private_reg?
          end

          write_dependency_files(package_files) do |file|
            prepared_package_json_content(file)
          end
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_locks
          @package_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("package-lock.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def yarn_locks
          @yarn_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("yarn.lock") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def pnpm_locks
          @pnpm_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("pnpm-lock.yaml") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def root_yarn_lock
          @root_yarn_lock ||= T.let(
            dependency_files
            .find { |f| f.name == "yarn.lock" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def root_pnpm_lock
          @root_pnpm_lock ||= T.let(
            dependency_files
            .find { |f| f.name == "pnpm-lock.yaml" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def shrinkwraps
          @shrinkwraps ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("npm-shrinkwrap.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def lockfiles
          [*package_locks, *shrinkwraps, *yarn_locks, *pnpm_locks]
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_files
          @package_files ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("package.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { void }
        def write_lockfiles
          write_dependency_files(yarn_locks) do |file|
            prepared_yarn_lockfile_content(T.must(file.content))
          end

          write_dependency_files([*package_locks, *shrinkwraps, *pnpm_locks]) do |file|
            T.must(file.content)
          end
        end

        sig do
          params(
            files: T::Array[Dependabot::DependencyFile],
            _blk: T.proc.params(file: Dependabot::DependencyFile).returns(String)
          ).void
        end
        def write_dependency_files(files, &_blk)
          dependency_file_entries_with_temp_paths(files).each do |path, file|
            write_dependency_file_at_path(path: path, original_file_name: file.name, content: yield(file))
          end
        end

        sig do
          params(
            files: T::Array[Dependabot::DependencyFile]
          ).returns(T::Array[[String, Dependabot::DependencyFile]])
        end
        def dependency_file_entries_with_temp_paths(files)
          files
            .map { |file| [temporary_path_for(file), file] }
            .sort_by do |path, file|
              [path, file.path, file.name]
            end
        end

        sig { params(file: Dependabot::DependencyFile, content: String).void }
        def write_dependency_file(file:, content:)
          write_dependency_file_at_path(
            path: temporary_path_for(file),
            original_file_name: file.name,
            content: content
          )
        end

        sig { params(path: String, original_file_name: String, content: String).void }
        def write_dependency_file_at_path(path:, original_file_name:, content:)
          if path.empty?
            raise Dependabot::DependabotError,
                  "Invalid dependency file path: #{original_file_name}"
          end

          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, content)
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def temporary_path_for(file)
          base_directory = job_directory
          normalized_path = Pathname.new(file.path).cleanpath
          relative_path = begin
            normalized_path.relative_path_from(base_directory).to_path
          rescue ArgumentError
            # Mixed absolute/relative path types can raise here; fall back to a
            # normalized local path and rely on segment clamping below.
            normalized_path.to_path.sub(%r{^/+}, "")
          end

          segments = relative_path.split("/").each_with_object([]) do |segment, memo|
            next if segment.empty? || segment == "."

            if segment == ".."
              memo.pop
              next
            end

            memo << segment
          end

          segments.join("/")
        end

        sig { returns(Pathname) }
        def job_directory
          @job_directory ||= T.let(
            begin
              base_file = package_files.min_by(&:path) || dependency_files.min_by(&:path)
              unless base_file
                raise Dependabot::DependabotError,
                      "Dependency files contain no source directories"
              end

              Pathname.new(base_file.directory).cleanpath
            end,
            T.nilable(Pathname)
          )

          @job_directory
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T::Boolean) }
        def yarnrc_specifies_private_reg?
          return false unless yarnrc_file

          regex = Package::RegistryFinder::YARN_GLOBAL_REGISTRY_REGEX
          yarnrc_global_registry =
            yarnrc_file&.content
                       &.lines
                       &.find { |line| line.match?(regex) }
                       &.match(regex)
                       &.named_captures
                       &.fetch("registry")

          return false unless yarnrc_global_registry

          Package::RegistryFinder::CENTRAL_REGISTRIES.none? do |r|
            r.include?(T.must(URI(yarnrc_global_registry).host))
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity

        # Duplicated in NpmLockfileUpdater
        # Remove the dependency we want to update from the lockfile and let
        # yarn find the latest resolvable version and fix the lockfile
        sig { params(content: String).returns(String) }
        def prepared_yarn_lockfile_content(content)
          content.gsub(/^#{Regexp.quote(dependency.name)}\@.*?\n\n/m, "")
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def prepared_package_json_content(file)
          NpmAndYarn::FileUpdater::PackageJsonPreparer.new(
            package_json_content: T.must(file.content)
          ).prepared_content
        end

        sig { returns(String) }
        def npmrc_content
          NpmAndYarn::FileUpdater::NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def yarnrc_file
          dependency_files.find { |f| f.name == ".yarnrc" }
        end

        sig { returns(String) }
        def yarnrc_content
          NpmAndYarn::FileUpdater::NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).yarnrc_content
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def yarnrc_yml_file
          dependency_files.find { |f| f.name.end_with?(".yarnrc.yml") }
        end

        sig { returns(T.nilable(String)) }
        def yarnrc_yml_content
          yarnrc_yml_file&.content
        end
      end
    end
  end
end
