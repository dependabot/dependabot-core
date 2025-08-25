# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/npm_and_yarn/sub_dependency_files_filterer"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/npm_and_yarn/update_checker/dependency_files_builder"
require "dependabot/npm_and_yarn/version"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class SubdependencyVersionResolver
        extend T::Sig

        sig { returns(Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T.nilable(T.any(String, Gem::Version))) }
        attr_reader :latest_allowable_version

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig do
          params(
            dependency: Dependency,
            credentials: T::Array[Dependabot::Credential],
            dependency_files: T::Array[Dependabot::DependencyFile],
            ignored_versions: T::Array[String],
            latest_allowable_version: T.nilable(T.any(String, Gem::Version)),
            repo_contents_path: T.nilable(String)
          ).void
        end
        def initialize(dependency:, credentials:, dependency_files:,
                       ignored_versions:, latest_allowable_version:, repo_contents_path:)
          @dependency = dependency
          @credentials = credentials
          @dependency_files = dependency_files
          @ignored_versions = ignored_versions
          @latest_allowable_version = latest_allowable_version
          @repo_contents_path = repo_contents_path
        end

        sig { returns(T.nilable(T.any(String, Gem::Version))) }
        def latest_resolvable_version
          raise "Not a subdependency!" if dependency.requirements.any?
          return if bundled_dependency?

          base_dir = T.must(dependency_files.first).directory
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

        sig { params(lockfile: Dependabot::DependencyFile).returns(String) }
        def update_subdependency_in_lockfile(lockfile)
          lockfile_name = Pathname.new(lockfile.name).basename.to_s
          path = Pathname.new(lockfile.name).dirname.to_s

          updated_files = if lockfile.name.end_with?("yarn.lock") && Helpers.yarn_berry?(lockfile)
                            run_yarn_berry_updater(path, lockfile_name)
                          elsif lockfile.name.end_with?("yarn.lock")
                            run_yarn_updater(path, lockfile_name)
                          elsif lockfile.name.end_with?("pnpm-lock.yaml")
                            run_pnpm_updater(path, lockfile_name)
                          elsif lockfile.name.end_with?("bun.lock")
                            run_bun_updater(path, lockfile_name)
                          elsif !Helpers.parse_npm8?(lockfile)
                            run_npm6_updater(path, lockfile_name)
                          else
                            run_npm_updater(path, lockfile_name)
                          end

          updated_files.fetch(lockfile_name)
        end

        sig { params(updated_lockfiles: T::Array[Dependabot::DependencyFile]).returns(T.nilable(Gem::Version)) }
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

        sig { params(path: String, lockfile_name: String).returns(T::Hash[String, String]) }
        def run_yarn_updater(path, lockfile_name)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              T.cast(
                SharedHelpers.run_helper_subprocess(
                  command: NativeHelpers.helper_path,
                  function: "yarn:updateSubdependency",
                  args: [Dir.pwd, lockfile_name, [dependency.to_h]]
                ),
                T::Hash[String, String]
              )
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          unfindable_str = "find package \"#{dependency.name}"
          raise unless e.message.include?("The registry may be down") ||
                       e.message.include?("ETIMEDOUT") ||
                       e.message.include?("ENOBUFS") ||
                       e.message.include?(unfindable_str)

          retry_count ||= 0
          retry_count += 1
          raise if retry_count > 2

          sleep(rand(3.0..10.0))
          retry
        end

        sig { params(path: String, lockfile_name: String).returns(T::Hash[String, String]) }
        def run_yarn_berry_updater(path, lockfile_name)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              Helpers.run_yarn_command(
                "up -R #{dependency.name} #{Helpers.yarn_berry_args}".strip,
                fingerprint: "up -R <dependency_name> #{Helpers.yarn_berry_args}".strip
              )
              { lockfile_name => File.read(lockfile_name) }
            end
          end
        end

        sig { params(path: String, lockfile_name: String).returns(T::Hash[String, String]) }
        def run_pnpm_updater(path, lockfile_name)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              Helpers.run_pnpm_command(
                "update #{dependency.name} --lockfile-only",
                fingerprint: "update <dependency_name> --lockfile-only"
              )
              { lockfile_name => File.read(lockfile_name) }
            end
          end
        end

        sig { params(path: String, lockfile_name: String).returns(T::Hash[String, String]) }
        def run_npm_updater(path, lockfile_name)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              NativeHelpers.run_npm8_subdependency_update_command([dependency.name])

              { lockfile_name => File.read(lockfile_name) }
            end
          end
        end

        sig { params(path: String, lockfile_name: String).returns(T::Hash[String, String]) }
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

        sig { params(path: String, lockfile_name: String).returns(T::Hash[String, String]) }
        def run_npm6_updater(path, lockfile_name)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              SharedHelpers.run_helper_subprocess(
                command: NativeHelpers.helper_path,
                function: "npm6:updateSubdependency",
                args: [Dir.pwd, lockfile_name, [dependency.to_h]]
              )
            end
          end
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(Dependabot::Dependency) }
        def updated_dependency
          Dependabot::Dependency.new(
            name: dependency.name,
            version: T.cast(latest_allowable_version, T.nilable(T.any(String, Dependabot::Version))),
            previous_version: dependency.version,
            requirements: [],
            package_manager: dependency.package_manager,
            origin_files: dependency.origin_files,
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def filtered_lockfiles
          @filtered_lockfiles ||= T.let(
            SubDependencyFilesFilterer.new(
              dependency_files: dependency_files,
              updated_dependencies: [updated_dependency]
            ).files_requiring_update,
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(Dependabot::NpmAndYarn::UpdateChecker::DependencyFilesBuilder) }
        def dependency_files_builder
          @dependency_files_builder ||= T.let(
            DependencyFilesBuilder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials
            ),
            T.nilable(Dependabot::NpmAndYarn::UpdateChecker::DependencyFilesBuilder)
          )
        end

        sig { returns(T::Boolean) }
        def bundled_dependency?
          dependency.subdependency_metadata
                    &.any? { |h| h.fetch(:npm_bundled, false) } ||
            false
        end
      end
    end
  end
end
