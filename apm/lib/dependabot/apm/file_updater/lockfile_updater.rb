# typed: strong
# frozen_string_literal: true

require "fileutils"
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

        APM_MODULES_DIRECTORY = "apm_modules"

        AUTHENTICATION_FAILED_REGEX = /Authentication failed for '(?<url>[^']+)'/
        REPOSITORY_NOT_FOUND_REGEX = /repository '(?<url>[^']+)' not found/i
        # APM replaces git's error with its own when a clone is rejected or the
        # repository is missing, e.g. "Failed to clone repository x/y.
        # Authentication failed for clone on github.com."
        APM_AUTHENTICATION_FAILED_REGEX = /
          Failed\sto\sclone\srepository\s(?<repo>[^\s:]+?)\.\s
          Authentication\sfailed\sfor\s[^\n]*?\son\s(?<host>\S+?)\.(?=\s|\z)
        /x
        FAILURE_PREFIX = /Failed\sto\sdownload\sdependency\s|Failed\sto\sresolve\stransitive\sdep\s/
        # One failed package: its name (with an optional transitive `(via …)`
        # chain) and the diagnostic up to the next failure in APM's output.
        PACKAGE_FAILURE_REGEX = /
          (?:#{FAILURE_PREFIX})(?<name>\S+?)(?:\s\(via\s[^)]*\))?:\s
          (?<detail>.*?)(?=\n\s*\+-\s|#{FAILURE_PREFIX}|\z)
        /mx
        MISSING_REFERENCE_REGEX =
          /Remote\sbranch\s\S+\snot\sfound|Reference\s'[^']+'\snot\sfound|Could\snot\sresolve\s(?:commit|reference)/x

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
            # `apm lock` downloads packages into apm_modules/ and resolves
            # transitive dependencies from what is already there. The git reset
            # between updates doesn't remove that ignored directory, so clear it
            # to keep one update's packages from leaking into the next.
            FileUtils.rm_rf(APM_MODULES_DIRECTORY)
            File.write(FileUpdater::MANIFEST_FILENAME, manifest_content)
            File.write(FileUpdater::LOCKFILE_FILENAME, prepared_lockfile_content)

            SharedHelpers.with_git_configured(credentials: credentials) do
              NativeHelpers.run_apm_command("lock")
            end

            File.read(FileUpdater::LOCKFILE_FILENAME)
          ensure
            FileUtils.rm_rf(APM_MODULES_DIRECTORY)
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

          unreachable_url = unreachable_repository_url(message)
          raise Dependabot::GitDependenciesNotReachable, unreachable_url if unreachable_url

          missing_reference = package_with_missing_reference(message)
          raise Dependabot::GitDependencyReferenceNotFound, missing_reference if missing_reference

          raise Dependabot::DependencyFileNotResolvable, message
        end

        sig { params(message: String).returns(T.nilable(String)) }
        def unreachable_repository_url(message)
          git_url = message.match(AUTHENTICATION_FAILED_REGEX)&.[](:url) ||
                    message.match(REPOSITORY_NOT_FOUND_REGEX)&.[](:url)
          return git_url if git_url

          apm_failure = message.match(APM_AUTHENTICATION_FAILED_REGEX)
          "https://#{apm_failure[:host]}/#{apm_failure[:repo]}" if apm_failure
        end

        # Checks each failed package's own diagnostic, so a missing ref is
        # attributed to the package it belongs to rather than an earlier failure.
        sig { params(message: String).returns(T.nilable(String)) }
        def package_with_missing_reference(message)
          position = 0
          while (failure = PACKAGE_FAILURE_REGEX.match(message, position))
            return failure[:name] if failure[:detail].to_s.match?(MISSING_REFERENCE_REGEX)

            position = failure.end(0)
          end
          nil
        end
      end
    end
  end
end
