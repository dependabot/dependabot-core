# typed: strong
# frozen_string_literal: true

require "fileutils"
require "json"
require "sorbet-runtime"

require "dependabot/shared_helpers"
require "dependabot/command_helpers"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/lockfile/env"
require "dependabot/github_actions/lockfile/errors"
require "dependabot/github_actions/lockfile/reader"

module Dependabot
  module GithubActions
    module Lockfile
      # Shells out to gh-actions-lock to regenerate actions.lock.
      class CliEngine
        extend T::Sig

        JsonObject = T.type_alias { T::Hash[String, Object] }
        FIXED_FINDING_CATEGORIES = %w(onboarding-required ref-changed stale).freeze
        UNRESOLVABLE_CATEGORIES = %w(
          unreachable-pin repo-replaced repo-unavailable repo-renamed not-pinned
          local-action invalid-self-repository-ref misleading-sha
        ).freeze

        # Host-identity failures from the engine: the lock is bound to a host it can't
        # be verified on. User-actionable (restore/regenerate), never retryable. The
        # engine wraps every lookup error, so only a 404 counts; 5xx/429/403/timeouts stay EngineError.
        HOST_IDENTITY_ERROR = /verifying repository identity .*: HTTP 404\b|repository IDs|not the selected host/

        # `hostname` is the repository's home host. The engine binds every pin with an
        # omitted lockfile `hostname` to it, so it must never be guessed.
        sig { params(credentials: T::Array[Dependabot::Credential], hostname: String).void }
        def initialize(credentials, hostname: GITHUB_COM)
          @credentials = credentials
          @hostname = hostname
        end

        # Binary baked into the ecosystem image; falls back to PATH for local dev.
        sig { returns(String) }
        def self.binary_path
          base = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
          base ? File.join(base, "github_actions", "bin", "gh-actions-lock") : "gh-actions-lock"
        end

        # Re-pins workflows already tracked in the lockfile. `--no-onboard` refuses new
        # workflows/actions (surfaced as onboarding-required skips); `--no-narrow`
        # keeps the exact ref Dependabot wrote.
        sig do
          params(
            workflow_files: T::Array[Dependabot::DependencyFile],
            lockfile: Dependabot::DependencyFile,
            workflow_paths: T::Array[String],
            action_files: T::Array[Dependabot::DependencyFile]
          ).returns(String)
        end
        def relock(
          workflow_files:,
          lockfile:,
          workflow_paths: workflow_files.map { |file| repo_path(file) },
          action_files: []
        )
          in_repo(workflow_files + action_files, lockfile) do |dir|
            args = %w(--no-onboard --no-narrow --no-interactive --json=findings) +
                   ["--hostname", hostname] + workflow_paths
            json, exit_status = run(dir, args)

            skipped = onboarding_skips(json, lockfile)
            log_skips(skipped)

            # `findings` is the PRE-fix diagnosis; at exit 0 fix-mode already resolved
            # them. Writes are all-or-nothing, so exit 1 means nothing was written.
            raise_on_findings(json) if exit_status == 1

            File.read(File.join(dir, LOCKFILE_PATH))
          end
        end

        private

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(String) }
        attr_reader :hostname

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
        sig { params(dir: String, args: T::Array[String]).returns([JsonObject, Integer]) }
        def run(dir, args)
          stdout, stderr, exit_status = invoke(dir, args)
          raise DependencyFileNotResolvable, stderr.strip if exit_status > 1 && stderr.match?(HOST_IDENTITY_ERROR)
          raise EngineError, "gh-actions-lock failed (exit #{exit_status}): #{stderr.strip}" if exit_status > 1

          json = case (parsed = JSON.parse(stdout))
                 when Hash then parsed
                 else raise EngineError, "gh-actions-lock emitted non-object JSON"
                 end

          [json, exit_status]
        rescue JSON::ParserError => e
          raise EngineError, "gh-actions-lock emitted unparseable JSON: #{e.message}"
        end

        # Runs the binary with no shell (argv array, no escaping) and returns
        # [stdout, stderr, exit_status].
        sig { params(dir: String, args: T::Array[String]).returns([String, String, Integer]) }
        def invoke(dir, args)
          # The temp dir has no .git, so name the root that `$/` paths resolve against.
          env = Env.build(credentials, hostname).merge("GH_ACTIONS_LOCK_REPO_ROOT" => dir)
          env_cmd = [env, self.class.binary_path, *args, { chdir: dir }]
          stdout, stderr, process = CommandHelpers.capture3_with_timeout(env_cmd)

          # A failed spawn comes back as a nil status, not an exception.
          if process.nil?
            raise EngineError,
                  "gh-actions-lock failed to start (#{self.class.binary_path}): #{stderr.to_s.strip}"
          end
          raise EngineError, "gh-actions-lock terminated by signal #{process.termsig}" if process.termsig

          [stdout || "", stderr || "", process.exitstatus]
        end

        # Exit 1 wrote nothing. Any user-actionable finding wins; anything else retries.
        sig { params(json: JsonObject).void }
        def raise_on_findings(json)
          errors = T.cast(Array(json["findings"]), T::Array[JsonObject])
                    .select { |finding| finding["severity"].nil? || finding["severity"] == "error" }
          unresolvable = errors.find { |finding| UNRESOLVABLE_CATEGORIES.include?(finding["category"].to_s) }
          if unresolvable
            raise UnresolvableDependency.new(
              (unresolvable["dependency"] || "unknown").to_s,
              (unresolvable["detail"] || unresolvable["category"]).to_s
            )
          end

          categories = errors.map { |finding| finding["category"].to_s }.uniq - FIXED_FINDING_CATEGORIES
          raise EngineError, "gh-actions-lock exited 1 without an actionable finding: #{categories.inspect}"
        end

        # Partitions onboarding-required findings into genuine skips vs. a lock the
        # engine could not read. The discriminator is the action, not the path: a
        # finding is contradictory iff the lock already pins its `dependency` under its
        # `workflow`. A finding with no `dependency` falls back to the path check.
        sig do
          params(json: JsonObject, lockfile: Dependabot::DependencyFile)
            .returns(T::Array[String])
        end
        def onboarding_skips(json, lockfile)
          findings = T.cast(Array(json["findings"]), T::Array[JsonObject])
          onboarding = findings.select { |finding| finding["category"] == "onboarding-required" }
          return [] if onboarding.empty?

          reader = Reader.from_files([lockfile])
          contradictory, strays = onboarding.partition { |finding| lock_contradicts?(reader, finding) }

          raise_lockfile_unrecognized(contradictory) if contradictory.any?

          strays.map { |finding| workflow_for(finding) }.uniq
        end

        # True when an onboarding-required finding contradicts a lock we can read.
        sig { params(reader: T.nilable(Reader), finding: JsonObject).returns(T::Boolean) }
        def lock_contradicts?(reader, finding)
          return false unless reader

          action = finding["dependency"].to_s
          workflow = workflow_for(finding)
          return reader.pins_action?(workflow, action) unless action.empty?

          reader.onboarded?(workflow)
        end

        sig { params(finding: JsonObject).returns(String) }
        def workflow_for(finding)
          (finding["workflow"] || finding["dependency"] || "unknown").to_s
        end

        # The engine reported lock-tracked workflows as un-onboarded: it could not read
        # the lock and treated it as empty. Fail with a lockfile error, not a crash.
        sig { params(findings: T::Array[JsonObject]).void }
        def raise_lockfile_unrecognized(findings)
          paths = findings.map { |finding| workflow_for(finding) }
          slice_keys = %w(workflow dependency category severity detail)
          Dependabot.logger.debug(
            "gh-actions-lock reported lockfile-tracked workflow(s) as un-onboarded " \
            "(lock unreadable): #{findings.map { |f| f.slice(*slice_keys) }}"
          )
          raise Dependabot::DependencyFileNotParseable.new(
            LOCKFILE_PATH,
            "gh-actions-lock could not read #{LOCKFILE_PATH} as covering #{paths.join(', ')}, even " \
            "though the lockfile tracks #{paths.length == 1 ? 'that workflow' : 'those workflows'}. " \
            "The lockfile is likely malformed or unreadable by the engine: every dependencies entry " \
            "must include #{Reader::REQUIRED_DEPENDENCY_KEYS.join(', ')}, or the engine silently " \
            "treats the whole lockfile as empty. No changes were made."
          )
        end

        sig { params(skipped: T::Array[String]).void }
        def log_skips(skipped)
          return if skipped.empty?

          Dependabot.logger.info(
            "gh-actions-lock skipped onboarding in #{skipped.size} workflow(s) (no-onboard is " \
            "update's default; skipped actions remain untracked, not failed): #{skipped.join(', ')}"
          )
        end
      end
    end
  end
end
