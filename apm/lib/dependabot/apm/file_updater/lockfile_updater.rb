# typed: strong
# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"
require "shellwords"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters/vendor_updater"
require "dependabot/shared_helpers"
require "dependabot/workspace"
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
      # A branch pin's ref doesn't change, so `apm install` keeps its locked
      # commit. When installing, the branch is then moved the way APM moves
      # one, with `apm update` for that package (see #install_commands). For
      # `apm lock`, which deploys nothing, its lock entry is first moved to the
      # branch's new head commit for APM to verify and re-hash.
      class LockfileUpdater
        extend T::Sig

        # The regenerated lockfile and the committed deployed files
        # `apm install` changed alongside it.
        class Result < T::Struct
          const :lockfile_content, String
          const :deployed_files, T::Array[Dependabot::DependencyFile]
        end

        APM_MODULES_DIRECTORY = "apm_modules"
        # With the CI variable set, APM verifies a committed lockfile as if
        # `--frozen` were passed, which fails on the manifest just edited.
        INSTALL_COMMAND = "install --no-frozen"
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
          @result = T.let(nil, T.nilable(Result))
        end

        sig { returns(String) }
        def updated_lockfile_content
          result.lockfile_content
        end

        # The deployed files `apm install` added, changed or removed that the
        # repository commits. Git reports only tracked and untracked files,
        # never ignored ones, so a repository that ignores its deployed files
        # gets none.
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_deployed_files
          result.deployed_files
        end

        private

        sig { returns(Result) }
        def result
          @result ||= regenerate
        end

        sig { returns(Result) }
        def regenerate
          SharedHelpers.in_a_temporary_repo_directory(lockfile.directory, repo_contents_path) do
            regenerated = T.let(nil, T.nilable(Result))
            # APM downloads packages into apm_modules/ and resolves
            # transitive dependencies from what is already there. The git reset
            # between updates doesn't remove that ignored directory, so clear it
            # to keep one update's packages from leaking into the next.
            FileUtils.rm_rf(APM_MODULES_DIRECTORY)
            File.write(FileUpdater::MANIFEST_FILENAME, manifest_content)

            command = apm_command
            install = command.start_with?("install")
            File.write(FileUpdater::LOCKFILE_FILENAME, install ? T.must(lockfile.content) : prepared_lockfile_content)
            check_deployed_files_unedited if install

            SharedHelpers.with_git_configured(credentials: credentials) do
              (install ? install_commands(command) : [command]).each do |apm_args|
                NativeHelpers.run_apm_command(apm_args)
              end
            end

            content = File.read(FileUpdater::LOCKFILE_FILENAME)
            # `apm lock` deploys nothing, so only an install changes deployed
            # files, and they must be read before its output is cleaned up.
            regenerated = Result.new(
              lockfile_content: content,
              deployed_files: install ? changed_deployed_files(content) : []
            )
          ensure
            remove_apm_output(regenerated)
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_apm_error(e)
        end

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
          return INSTALL_COMMAND if Targets.declared_in_manifest?(manifest_content)

          recorded = Lockfile.new(lockfile)
          targets = recorded.deployment_targets
          return "lock" if targets.empty?

          targets &= supported_targets
          return "lock" if targets.empty? || (recorded.service_runtimes - targets).any?

          "#{INSTALL_COMMAND} --target #{targets.join(',')}"
        end

        # `apm install` re-resolves only the entries whose manifest ref changed,
        # so updated branch pins are then moved by `apm update`, as APM moves a
        # branch. That needs the lockfile to still name the commit the
        # committed files were deployed from: on a fresh checkout, with no
        # deployment receipts, APM only replaces a deployed skill whose whole
        # tree matches the locked commit's output or the new one's. The install
        # is skipped when every update is a branch pin.
        sig { params(install_command: String).returns(T::Array[String]) }
        def install_commands(install_command)
          branch_pins = updated_branch_pins
          return [install_command] if branch_pins.empty?

          commands = [branch_update_command(install_command, branch_pins.keys)]
          commands.unshift(install_command) unless dependencies.all? { |dependency| branch_pin_update?(dependency) }
          commands
        end

        # `apm update` takes the install's targets, `--yes` because it
        # otherwise asks for confirmation, and APM's name for each package,
        # which it reads from the package's lock entry (see
        # Lockfile#package_name). Dependabot's lockfile key drops the port, so
        # it only stands in, with the virtual path joined by `/`, for a
        # package that isn't locked yet.
        sig { params(install_command: String, keys: T::Array[String]).returns(String) }
        def branch_update_command(install_command, keys)
          recorded = Lockfile.new(lockfile)
          packages = keys.map { |key| Shellwords.escape(recorded.package_name(key) || key.sub("//", "/")) }
          "update --yes#{install_command.delete_prefix(INSTALL_COMMAND)} #{packages.join(' ')}"
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

        # A fresh checkout has none of the local deployment receipts APM keeps
        # outside the repository, so `apm install` can't tell a committed
        # deployed file that was edited from one it may overwrite. It refuses
        # every file of a package with an edited file, even a package whose
        # version doesn't change, and fails with one error per file. The
        # update fails first instead, naming only the edited files.
        sig { void }
        def check_deployed_files_unedited
          root = File.realpath(Dir.pwd)
          edited = T.let([], T::Array[String])
          Lockfile.new(lockfile).deployed_file_hashes.each do |path, digest|
            next unless digest.start_with?(SHA256_PREFIX) && file_in_checkout?(path, root)

            edited << path unless apm_file_digest(path) == digest.delete_prefix(SHA256_PREFIX)
          end
          raise Dependabot::DependencyFileNotResolvable, edited_files_message(edited) if edited.any?
        end

        # Hashes a deployed file the way APM's compute_file_hash
        # (apm_cli/utils/content_hash.py) does: text, meaning valid UTF-8
        # with no NUL byte, has CRLF collapsed to LF, so a CRLF checkout or
        # a CRLF upstream file matches the digest APM recorded. A bare CR
        # still counts, and anything else is hashed raw.
        sig { params(path: String).returns(String) }
        def apm_file_digest(path)
          content = File.binread(path)
          text = !content.include?("\0") && content.dup.force_encoding(Encoding::UTF_8).valid_encoding?
          Digest::SHA256.hexdigest(text ? content.gsub("\r\n", "\n") : content)
        end

        sig { params(paths: T::Array[String]).returns(String) }
        def edited_files_message(paths)
          "These committed deployed files have been edited since APM deployed them: #{paths.sort.join(', ')}. " \
            "On a fresh checkout APM has no local deployment receipt for them, so `apm install` refuses to " \
            "overwrite them or any other file of their package. Revert the edits, or move the whole deployed " \
            "directory that holds each edited file (for a skill, its skill directory) out of the checkout, " \
            "so Dependabot can update the package. Moving only the edited files leaves a partial deployment " \
            "that APM still refuses."
        end

        sig { params(path: String, root: String).returns(T::Boolean) }
        def file_in_checkout?(path, root)
          return false if Pathname.new(path).absolute? || !File.file?(path) || File.symlink?(path)

          File.realpath(path).start_with?("#{root}#{File::SEPARATOR}")
        end

        # Collects, as git status reports them, the changes under every path
        # the old or new lockfile records as deployed: a file a new version
        # adds is recorded only in the new lockfile, and one it drops only in
        # the old. They're flagged as vendored, so a grouped update carries
        # them to the pull request without handing them to the next update as
        # dependency files. Git status doesn't give each file's mode, and the
        # pull request writes a file without one as 100644, so each written
        # file's mode is read from disk to keep scripts executable.
        sig { params(new_lockfile_content: String).returns(T::Array[Dependabot::DependencyFile]) }
        def changed_deployed_files(new_lockfile_content)
          project_root = repo_contents_path
          return [] unless project_root

          new_lockfile = Dependabot::DependencyFile.new(
            name: FileUpdater::LOCKFILE_FILENAME,
            content: new_lockfile_content
          )
          roots = deployment_roots(Lockfile.new(lockfile).deployed_paths + Lockfile.new(new_lockfile).deployed_paths)
          return [] if roots.empty?

          Dependabot::FileUpdaters::VendorUpdater
            .new(repo_contents_path: project_root, vendor_dir: ".")
            .updated_vendor_cache_files(base_directory: lockfile.directory)
            .select { |file| deployed_file?(file.name, roots) }
            .each do |file|
              next if file.deleted?

              file.mode = file_mode(File.join(project_root, lockfile.directory, file.name))
            end
        end

        sig { params(path: String).returns(String) }
        def file_mode(path)
          File.executable?(path) ? Dependabot::DependencyFile::Mode::EXECUTABLE : Dependabot::DependencyFile::Mode::FILE
        end

        # The recorded paths as clean relative paths inside the project. An
        # absolute path, one leading out of it, or the project itself is
        # dropped, so nothing outside what APM deploys is reported.
        sig { params(paths: T::Array[String]).returns(T::Array[String]) }
        def deployment_roots(paths)
          paths.filter_map do |path|
            clean = Pathname.new(path).cleanpath
            next if clean.absolute?

            root = clean.to_s
            root unless root == "." || root == ".." || root.start_with?("../")
          end.uniq
        end

        sig { params(name: String, roots: T::Array[String]).returns(T::Boolean) }
        def deployed_file?(name, roots)
          return false if [FileUpdater::MANIFEST_FILENAME, FileUpdater::LOCKFILE_FILENAME].include?(name)
          return false if name.start_with?("#{APM_MODULES_DIRECTORY}/")

          roots.any? { |root| name == root || name.start_with?("#{root}/") }
        end

        # `apm install` deploys files, and the git reset between updates keeps
        # ignored directories, so a later update in the same checkout would
        # find files it doesn't own. The checkout starts as a clean clone, so
        # every untracked file here was written by APM.
        # A grouped update commits each update's changes to its workspace
        # before the next one runs, so the files this update returns as
        # created are written back: the workspace then matches what it
        # returned, and the next update doesn't report them as created again.
        sig { params(regenerated: T.nilable(Result)).void }
        def remove_apm_output(regenerated)
          FileUtils.rm_rf(APM_MODULES_DIRECTORY)
          return unless repo_contents_path

          SharedHelpers.run_shell_command("git clean -fdx -- .", fingerprint: "git clean -fdx -- .")
          return unless regenerated && Dependabot::Workspace.active_workspace

          regenerated.deployed_files.each { |file| restore_created_file(file) }
        end

        sig { params(file: Dependabot::DependencyFile).void }
        def restore_created_file(file)
          return unless file.operation == Dependabot::DependencyFile::Operation::CREATE

          path = File.join(T.must(repo_contents_path), lockfile.directory, file.name)
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, file.decoded_content)
          File.chmod(file.mode == Dependabot::DependencyFile::Mode::EXECUTABLE ? 0o755 : 0o644, path)
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

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def branch_pin_update?(dependency)
          new_commit = dependency.version
          return false if new_commit.nil? || new_commit == dependency.previous_version

          dependency.requirements.all? do |requirement|
            !requirement.metadata_string("lockfile_key").nil? && !requirement.source_string("branch").nil?
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
