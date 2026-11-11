# typed: strong
# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/apm/file_updater"
require "dependabot/apm/lockfile"
require "dependabot/apm/native_helpers"
require "dependabot/apm/targets"

module Dependabot
  module Apm
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Regenerates `apm.lock.yaml` for the updated manifest. It runs
      # `apm install` when it can tell which harnesses to deploy to (see
      # #apm_command): `apm lock` doesn't deploy, so it would keep the old
      # version's deployed file list and hashes, which `apm install --frozen`
      # rejects. Otherwise it runs `apm lock`, which needs no harness. APM only
      # re-resolves the entries whose manifest ref changed, keeping every other
      # entry on its locked commit, so tag and SHA updates are picked up from
      # the manifest.
      # A branch pin's ref doesn't change, so its lock entry is first moved to
      # the branch's new head commit for APM to verify and re-hash.
      class LockfileUpdater
        extend T::Sig

        APM_MODULES_DIRECTORY = "apm_modules"
        SHA256_PREFIX = "sha256:"

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
        # Diagnostics that show a ref is missing. APM's own "Could not resolve
        # commit/reference" wrapper is deliberately not matched: it wraps any
        # failure, including network errors, so only the detail it carries
        # (APM's or git's) says whether the ref exists.
        MISSING_REFERENCE_REGEX = /
          Remote\sbranch\s\S+\snot\sfound|
          Reference\s'[^']+'\snot\sfound|
          Needed\sa\ssingle\srevision|
          unable\sto\sread\stree|
          did\snot\smatch\sany\sfile\(s\)\sknown\sto\sgit|
          reference\sis\snot\sa\stree
        /x

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
            # APM downloads packages into apm_modules/ and resolves
            # transitive dependencies from what is already there. The git reset
            # between updates doesn't remove that ignored directory, so clear it
            # to keep one update's packages from leaking into the next.
            FileUtils.rm_rf(APM_MODULES_DIRECTORY)
            File.write(FileUpdater::MANIFEST_FILENAME, manifest_content)
            File.write(FileUpdater::LOCKFILE_FILENAME, prepared_lockfile_content)

            command = apm_command
            remove_unmodified_deployed_files if command.start_with?("install")

            SharedHelpers.with_git_configured(credentials: credentials) do
              NativeHelpers.run_apm_command(command)
            end

            File.read(FileUpdater::LOCKFILE_FILENAME)
          ensure
            remove_apm_output
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_apm_error(e)
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

        # Chooses targets in the order `apm audit` does: the manifest's, then
        # the lockfile's. Passing the recorded targets keeps `apm install` from
        # auto-detecting harnesses from the checkout, where ignored harness
        # directories are missing. APM maps some MCP runtimes (e.g. `intellij`)
        # to a different file target, which `--target` can't express, so a
        # service runtime outside the recorded targets falls back to `apm lock`.
        sig { returns(String) }
        def apm_command
          return "install" if Targets.declared_in_manifest?(manifest_content)

          recorded = Lockfile.new(lockfile)
          targets = recorded.deployment_targets
          return "lock" if targets.empty?

          targets &= supported_targets
          return "lock" if targets.empty? || (recorded.service_runtimes - targets).any?

          "install --target #{targets.join(',')}"
        end

        # The harnesses the installed APM CLI supports, so a new APM release
        # needs no change here. Only stdout is parsed, because APM logs
        # warnings such as policy discovery to stderr.
        sig { returns(T::Array[String]) }
        def supported_targets
          Targets.supported(NativeHelpers.run_apm_command("targets --json --all", stderr_to_stdout: false))
        rescue SharedHelpers::HelperSubprocessFailed
          []
        end

        # Workaround for microsoft/apm#3391: without the local deployment
        # receipts APM 0.35.0 keeps outside the repository, `apm install` won't
        # overwrite deployed files a repository commits, then removes them as
        # stale, so the update deletes the skill. Removing each file that still
        # matches the digest the lockfile recorded lets APM deploy the new
        # version. An edited file is kept, and APM skips it with a warning.
        # Remove this once the bundled APM includes the fix for #3391.
        sig { void }
        def remove_unmodified_deployed_files
          root = File.realpath(Dir.pwd)
          Lockfile.new(lockfile).deployed_file_hashes.each do |path, digest|
            next unless digest.start_with?(SHA256_PREFIX) && file_in_checkout?(path, root)

            File.delete(path) if Digest::SHA256.file(path).hexdigest == digest.delete_prefix(SHA256_PREFIX)
          end
        end

        sig { params(path: String, root: String).returns(T::Boolean) }
        def file_in_checkout?(path, root)
          return false if Pathname.new(path).absolute? || !File.file?(path) || File.symlink?(path)

          File.realpath(path).start_with?("#{root}#{File::SEPARATOR}")
        end

        # `apm install` deploys files, and the git reset between updates keeps
        # ignored directories, so a later update in the same checkout would
        # find files it doesn't own. The checkout starts as a clean clone, so
        # every untracked file here was written by APM.
        sig { void }
        def remove_apm_output
          FileUtils.rm_rf(APM_MODULES_DIRECTORY)
          return unless repo_contents_path

          SharedHelpers.run_shell_command("git clean -fdx -- .", fingerprint: "git clean -fdx -- .")
        end

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
        def handle_apm_error(error)
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
