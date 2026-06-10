# typed: strict
# frozen_string_literal: true

require "fileutils"
require "json"
require "sorbet-runtime"

require "dependabot/shared_helpers"
require "dependabot/command_helpers"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/lockfile/engine"
require "dependabot/github_actions/lockfile/env"
require "dependabot/github_actions/lockfile/errors"
require "dependabot/github_actions/lockfile/reader"
require "dependabot/github_actions/lockfile/types"

module Dependabot
  module GithubActions
    module Lockfile
      # Engine that shells out to the real `gh-actions-pin` binary — the only
      # production engine. Hermetic tests stub {Engine.build} rather than this class.
      class CliEngine < Engine
        extend T::Sig

        # Binary baked into the ecosystem image; falls back to PATH for local dev.
        sig { returns(String) }
        def self.binary_path
          base = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
          base ? File.join(base, "github_actions", "bin", "gh-actions-pin") : "gh-actions-pin"
        end

        # Re-pins workflows already tracked in the lockfile. `--no-onboard` refuses new
        # workflows/actions (surfaced as onboarding-required skips); `--no-narrow`
        # keeps the exact ref Dependabot wrote.
        sig do
          override
            .params(
              workflow_files: T::Array[Dependabot::DependencyFile],
              lockfile: Dependabot::DependencyFile
            )
            .returns(RelockResult)
        end
        def relock(workflow_files:, lockfile:)
          in_repo(workflow_files, lockfile) do |dir|
            args = %w(check --no-onboard --no-narrow --no-interactive --json=workflows,findings,valid)
            json, exit_status = run(dir, args)

            # Collect skips before raising, so observability survives a co-occurring
            # blocker. A tracked-workflow onboarding-required means an unreadable lock.
            skipped = onboarding_skips(json, lockfile)
            log_skips(skipped)

            # `findings` is the PRE-fix diagnosis; at exit 0 fix-mode already resolved
            # them. Only exit 1 can carry a survivor (impostor/forgery or a skip).
            raise_on_findings(json) if exit_status == 1

            # The CLI owns the lock; Dependabot owns the workflow YAML. Read back the
            # re-pinned lock and log any unexpected workflow rewrite under --no-narrow.
            log_workflow_mismatch(json, read_back(dir, workflow_files))

            RelockResult.new(
              lockfile_content: File.read(File.join(dir, LOCKFILE_PATH)),
              skipped_workflows: skipped
            )
          end
        end

        private

        sig do
          type_parameters(:T)
            .params(
              workflow_files: T::Array[Dependabot::DependencyFile],
              lockfile: T.nilable(Dependabot::DependencyFile),
              blk: T.proc.params(dir: String).returns(T.type_parameter(:T))
            )
            .returns(T.type_parameter(:T))
        end
        def in_repo(workflow_files, lockfile, &blk)
          SharedHelpers.in_a_temporary_directory do |dir|
            (workflow_files + [lockfile].compact).each do |file|
              path = File.join(dir, repo_path(file))
              FileUtils.mkdir_p(File.dirname(path))
              File.write(path, file.content)
            end
            blk.call(dir.to_s) # rubocop:disable Performance/RedundantBlockCall
          end
        end

        # Repo-relative path (no leading slash) so the temp repo always mirrors the
        # real repository layout regardless of the Dependabot directory config.
        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def repo_path(file)
          file.path.delete_prefix("/")
        end

        # Invokes the binary and returns [parsed JSON, exit code]. Exit is tri-state:
        # 0 = valid, 1 = blocking findings (still well-formed JSON on stdout, parse it),
        # 2+ = tool failure (no usable JSON). JSON and exit are not interchangeable in
        # fix-mode: findings/valid are PRE-fix, exit is POST-fix, so callers gate on exit.
        sig { params(dir: String, args: T::Array[String]).returns([T::Hash[String, T.untyped], Integer]) }
        def run(dir, args)
          stdout, stderr, exit_status = invoke(dir, args)
          raise EngineError, "gh-actions-pin failed (exit #{exit_status}): #{stderr.strip}" if exit_status > 1

          [JSON.parse(stdout), exit_status]
        rescue JSON::ParserError => e
          raise EngineError, "gh-actions-pin emitted unparseable JSON: #{e.message}"
        end

        # Runs the binary with no shell (argv array, no escaping) and returns
        # [stdout, stderr, exit_status].
        sig { params(dir: String, args: T::Array[String]).returns([String, String, Integer]) }
        def invoke(dir, args)
          env_cmd = [Env.build(credentials), self.class.binary_path, *args, { chdir: dir }]
          stdout, stderr, process = CommandHelpers.capture3_with_timeout(env_cmd)

          # A failed spawn comes back as a nil status, not an exception.
          if process.nil?
            raise EngineError,
                  "gh-actions-pin failed to start (#{self.class.binary_path}): #{stderr.to_s.strip}"
          end

          [stdout || "", stderr || "", process.exitstatus || 0]
        end

        sig { params(json: T::Hash[String, T.untyped]).void }
        def raise_on_findings(json)
          Array(json["findings"]).each do |finding|
            # onboarding-required is a skip, collected separately; never raise on it.
            next if FindingMapper.onboarding_required?(finding)

            error = FindingMapper.error_for(finding)
            raise error if error
          end
        end

        # Partitions onboarding-required findings into genuine skips vs. a lock the
        # engine could not read. The discriminator is the action, not the path: a
        # finding is contradictory iff the lock already pins its `dependency` under its
        # `workflow`. A finding with no `dependency` falls back to the path check.
        sig do
          params(json: T::Hash[String, T.untyped], lockfile: Dependabot::DependencyFile)
            .returns(T::Array[SkippedWorkflow])
        end
        def onboarding_skips(json, lockfile)
          onboarding = Array(json["findings"]).select { |finding| FindingMapper.onboarding_required?(finding) }
          return [] if onboarding.empty?

          reader = Reader.from_files([lockfile])
          contradictory, strays = onboarding.partition { |finding| lock_contradicts?(reader, finding) }

          raise_lockfile_unrecognized(contradictory) if contradictory.any?

          strays.map { |finding| SkippedWorkflow.from_finding(finding) }
        end

        # True when an onboarding-required finding contradicts a lock we can read.
        sig { params(reader: T.nilable(Reader), finding: T::Hash[String, T.untyped]).returns(T::Boolean) }
        def lock_contradicts?(reader, finding)
          return false unless reader

          action = finding["dependency"].to_s
          workflow = SkippedWorkflow.from_finding(finding).workflow
          return reader.pins_action?(workflow, action) unless action.empty?

          reader.onboarded?(workflow)
        end

        # The engine reported lock-tracked workflows as un-onboarded: it could not read
        # the lock and treated it as empty. Fail with a lockfile error, not a crash.
        sig { params(findings: T::Array[T::Hash[String, T.untyped]]).void }
        def raise_lockfile_unrecognized(findings)
          paths = findings.map { |finding| SkippedWorkflow.from_finding(finding).workflow }
          slice_keys = %w(workflow dependency category severity detail)
          Dependabot.logger.debug(
            "gh-actions-pin reported lockfile-tracked workflow(s) as un-onboarded " \
            "(lock unreadable): #{findings.map { |f| f.slice(*slice_keys) }}"
          )
          raise Dependabot::DependencyFileNotParseable.new(
            LOCKFILE_PATH,
            "gh-actions-pin could not read #{LOCKFILE_PATH} as covering #{paths.join(', ')}, even " \
            "though the lockfile tracks #{paths.length == 1 ? 'that workflow' : 'those workflows'}. " \
            "The lockfile is likely malformed or unreadable by the engine: every dependencies entry " \
            "must include #{Reader::REQUIRED_DEPENDENCY_KEYS.join(', ')}, or the engine silently " \
            "treats the whole lockfile as empty. No changes were made."
          )
        end

        sig { params(skipped: T::Array[SkippedWorkflow]).void }
        def log_skips(skipped)
          return if skipped.empty?

          Dependabot.logger.info(
            "gh-actions-pin skipped #{skipped.size} un-onboarded workflow(s) (no-onboard is " \
            "update's default; left untracked, not failed): #{skipped.map(&:workflow).join(', ')}"
          )
        end

        # Defensive observability only (never raises): logs files we read as changed
        # but the engine did not report saving in workflows[].
        sig do
          params(json: T::Hash[String, T.untyped], updated_workflows: T::Hash[String, String]).void
        end
        def log_workflow_mismatch(json, updated_workflows)
          reported = Array(json["workflows"]).filter_map { |w| w.is_a?(Hash) ? w["path"] : nil }
          unreported = updated_workflows.keys.reject { |name| reported.include?(name) }
          return if unreported.empty?

          Dependabot.logger.debug(
            "gh-actions-pin rewrote workflow(s) not present in reported workflows[]: #{unreported.join(', ')}"
          )
        end

        sig do
          params(dir: String, workflow_files: T::Array[Dependabot::DependencyFile])
            .returns(T::Hash[String, String])
        end
        def read_back(dir, workflow_files)
          workflow_files.each_with_object({}) do |file, acc|
            updated = File.read(File.join(dir, repo_path(file)))
            acc[file.name] = updated unless updated == file.content
          end
        end
      end
    end
  end
end
