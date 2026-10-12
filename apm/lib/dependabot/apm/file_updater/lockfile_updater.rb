# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/apm/file_updater"
require "dependabot/apm/lockfile"
require "dependabot/apm/native_helpers"

module Dependabot
  module Apm
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Regenerates `apm.lock.yaml` with `apm lock`, which resolves the updated
      # manifest without deploying any package files. APM only re-resolves the
      # entries whose manifest ref changed, keeping every other entry on its
      # locked commit, so tag and SHA updates are picked up from the manifest.
      # A branch pin's ref doesn't change, so its lock entry is first moved to
      # the branch's new head commit for APM to verify and re-hash.
      class LockfileUpdater
        extend T::Sig

        AUTHENTICATION_FAILED_REGEX = /Authentication failed for '(?<url>[^']+)'/
        REPOSITORY_NOT_FOUND_REGEX = /repository '(?<url>[^']+)' not found/i
        REFERENCE_NOT_FOUND_REGEX = /
          Failed\sto\sdownload\sdependency\s(?<name>\S+?):.*
          (?:Remote\sbranch\s\S+\snot\sfound|Reference\s'[^']+'\snot\sfound|Could\snot\sresolve\s(?:commit|reference))
        /mx

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            lockfile: Dependabot::DependencyFile,
            manifest_content: String,
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String)
          ).void
        end
        def initialize(dependencies:, lockfile:, manifest_content:, credentials:, repo_contents_path:)
          @dependencies = dependencies
          @lockfile = lockfile
          @manifest_content = manifest_content
          @credentials = credentials
          @repo_contents_path = repo_contents_path
        end

        sig { returns(String) }
        def updated_lockfile_content
          SharedHelpers.in_a_temporary_repo_directory(lockfile.directory, repo_contents_path) do
            File.write(FileUpdater::MANIFEST_FILENAME, manifest_content)
            File.write(FileUpdater::LOCKFILE_FILENAME, prepared_lockfile_content)

            SharedHelpers.with_git_configured(credentials: credentials) do
              NativeHelpers.run_apm_command("lock")
            end

            File.read(FileUpdater::LOCKFILE_FILENAME)
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_apm_lock_error(e)
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :lockfile

        sig { returns(String) }
        attr_reader :manifest_content

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(String) }
        def prepared_lockfile_content
          branch_updates = updated_branch_pins
          return T.must(lockfile.content) if branch_updates.empty?

          parsed_lockfile = Lockfile.new(lockfile)
          branch_updates.each { |key, commit| parsed_lockfile.pin_commit(key, commit) }
          parsed_lockfile.to_yaml
        end

        # The new commit of each updated branch pin, keyed by its lockfile entry.
        sig { returns(T::Hash[String, String]) }
        def updated_branch_pins
          dependencies.each_with_object({}) do |dependency, pins|
            new_commit = dependency.version
            next if new_commit.nil? || new_commit == dependency.previous_version

            dependency.requirements.each do |requirement|
              key = requirement.metadata_string("lockfile_key")
              pins[key] = new_commit if key && requirement.source_string("branch")
            end
          end
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T.noreturn) }
        def handle_apm_lock_error(error)
          message = error.message

          unreachable_url = message.match(AUTHENTICATION_FAILED_REGEX)&.[](:url) ||
                            message.match(REPOSITORY_NOT_FOUND_REGEX)&.[](:url)
          raise Dependabot::GitDependenciesNotReachable, unreachable_url if unreachable_url

          missing_reference = message.match(REFERENCE_NOT_FOUND_REGEX)
          raise Dependabot::GitDependencyReferenceNotFound, T.must(missing_reference[:name]) if missing_reference

          raise Dependabot::DependencyFileNotResolvable, message
        end
      end
    end
  end
end
