# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/workspace/base"
require "dependabot/workspace/change_attempt"

module Dependabot
  module Workspace
    class Git < Base
      extend T::Sig
      extend T::Helpers

      USER = "dependabot[bot]"
      EMAIL = T.let("#{USER}@users.noreply.github.com".freeze, String)

      sig { returns(String) }
      attr_reader :initial_head_sha

      sig { params(path: T.any(Pathname, String)).void }
      def initialize(path)
        super
        @initial_head_sha = T.let(head_sha, String)
        configure_git
      end

      sig { returns(T::Boolean) }
      def changed?
        changes.any? || !changed_files(ignored_mode: "no").empty?
      end

      sig { override.returns(String) }
      def to_patch
        run_shell_command(
          "git diff --patch #{@initial_head_sha}.. .",
          fingerprint: "git diff --path <initial_head_sha>.. ."
        )
      end

      sig { override.returns(NilClass) }
      def reset!
        reset(initial_head_sha)
        clean
        run_shell_command("git stash clear")
        @change_attempts = []

        nil
      end

      sig do
        override
          .params(memo: T.nilable(String))
          .returns(T.nilable(T::Array[Dependabot::Workspace::ChangeAttempt]))
      end
      def store_change(memo = nil)
        return nil if changed_files(ignored_mode: "no").empty?

        debug("store_change - before: #{current_commit}")
        sha, diff = commit(memo)

        change_attempts << ChangeAttempt.new(self, id: sha, memo: memo, diff: diff)
      ensure
        debug("store_change - after: #{current_commit}")
      end

      protected

      sig do
        override
          .params(memo: T.nilable(String), error: T.nilable(StandardError))
          .returns(T.nilable(T::Array[Dependabot::Workspace::ChangeAttempt]))
      end
      def capture_failed_change_attempt(memo = nil, error = nil)
        return nil if changed_files(ignored_mode: "matching").empty? && error.nil?

        sha, diff = stash(memo)
        change_attempts << ChangeAttempt.new(self, id: sha, memo: memo, diff: diff, error: error)
      end

      private

      sig { returns(String) }
      def configure_git
        run_shell_command(%(git config user.name "#{USER}"), allow_unsafe_shell_command: true)
        run_shell_command(%(git config user.email "#{EMAIL}"), allow_unsafe_shell_command: true)
      end

      sig { returns(String) }
      def head_sha
        run_shell_command("git rev-parse HEAD").strip
      end

      sig { returns(String) }
      def last_stash_sha
        run_shell_command("git rev-parse refs/stash").strip
      end

      sig { returns(String) }
      def current_commit
        # Avoid emitting the user's commit message to logs if Dependabot hasn't made any changes
        return "Initial SHA: #{initial_head_sha}" if changes.empty?

        # Prints out the last commit in the format "<short-ref> <commit-message>"
        run_shell_command(%(git log -1 --pretty="%h% B"), allow_unsafe_shell_command: true).strip
      end

      sig { params(ignored_mode: String).returns(String) }
      def changed_files(ignored_mode: "traditional")
        run_shell_command(
          "git status --untracked-files=all --ignored=#{ignored_mode} --short .",
          fingerprint: "git status --untracked-files=all --ignored=<ignored_mode> --short ."
        ).strip
      end

      sig { params(memo: T.nilable(String)).returns([String, String]) }
      def stash(memo = nil)
        msg = memo || "workspace change attempt"
        run_shell_command("git add --all --force .")
        run_shell_command(
          %(git stash push --all -m "#{msg}"),
          fingerprint: "git stash push --all -m \"<msg>\"",
          allow_unsafe_shell_command: true
        )

        sha = last_stash_sha
        diff = run_shell_command(
          "git stash show --patch #{sha}",
          fingerprint: "git stash show --patch <sha>"
        )

        [sha, diff]
      end

      sig { params(memo: T.nilable(String)).returns([String, String]) }
      def commit(memo = nil)
        run_shell_command("git add #{path}")
        diff = run_shell_command("git diff --cached .")

        msg = memo || "workspace change"
        run_shell_command(
          %(git commit -m "#{msg}"),
          fingerprint: "git commit -m \"<msg>\"",
          allow_unsafe_shell_command: true
        )

        [head_sha, diff]
      end

      sig { params(sha: String).returns(String) }
      def reset(sha)
        run_shell_command(
          "git reset --hard #{sha}",
          fingerprint: "git reset --hard <sha>"
        )
      end

      sig { override.returns(String) }
      def clean
        run_shell_command("git clean -fx .")
      end

      sig { params(args: String, kwargs: T.any(T::Boolean, String)).returns(String) }
      def run_shell_command(*args, **kwargs)
        Dir.chdir(path) { T.unsafe(SharedHelpers).run_shell_command(*args, **kwargs) }
      end

      sig { params(message: String).void }
      def debug(message)
        Dependabot.logger.debug("[workspace] #{message}")
      end
    end
  end
end
