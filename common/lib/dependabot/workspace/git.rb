# typed: false
# frozen_string_literal: true

require "dependabot/workspace/base"
require "dependabot/workspace/change_attempt"

module Dependabot
  module Workspace
    class Git < Base
      USER = "dependabot[bot]"
      EMAIL = "#{USER}@users.noreply.github.com".freeze

      attr_reader :initial_head_sha

      def initialize(path)
        super(path)
        @initial_head_sha = head_sha
        configure_git
      end

      def changed?
        changes.any? || !changed_files.empty?
      end

      def to_patch
        run_shell_command("git diff --patch #{@initial_head_sha}.. .")
      end

      def reset!
        reset(initial_head_sha)
        clean
        run_shell_command("git stash clear")
        @change_attempts = []

        nil
      end

      def store_change(memo = nil)
        return nil if changed_files.empty?

        debug("store_change - before: #{current_commit}")
        sha, diff = commit(memo)

        change_attempts << ChangeAttempt.new(self, id: sha, memo: memo, diff: diff)
      ensure
        debug("store_change - after: #{current_commit}")
      end

      protected

      def capture_failed_change_attempt(memo = nil, error = nil)
        return nil if changed_files(ignored_mode: "matching").empty? && error.nil?

        sha, diff = stash(memo)
        change_attempts << ChangeAttempt.new(self, id: sha, memo: memo, diff: diff, error: error)
      end

      private

      def configure_git
        run_shell_command(%(git config user.name "#{USER}"), allow_unsafe_shell_command: true)
        run_shell_command(%(git config user.email "#{EMAIL}"), allow_unsafe_shell_command: true)
      end

      def head_sha
        run_shell_command("git rev-parse HEAD").strip
      end

      def last_stash_sha
        run_shell_command("git rev-parse refs/stash").strip
      end

      def current_commit
        # Avoid emiting the user's commit message to logs if Dependabot hasn't made any changes
        return "Initial SHA: #{initial_head_sha}" if changes.empty?

        # Prints out the last commit in the format "<short-ref> <commit-message>"
        run_shell_command(%(git log -1 --pretty="%h% B"), allow_unsafe_shell_command: true).strip
      end

      def changed_files(ignored_mode: "traditional")
        run_shell_command("git status --untracked-files=all --ignored=#{ignored_mode} --short .").strip
      end

      def stash(memo = nil)
        msg = memo || "workspace change attempt"
        run_shell_command("git add --all --force .")
        run_shell_command(%(git stash push --all -m "#{msg}"), allow_unsafe_shell_command: true)

        sha = last_stash_sha
        diff = run_shell_command("git stash show --patch #{sha}")

        [sha, diff]
      end

      def commit(memo = nil)
        run_shell_command("git add #{path}")
        diff = run_shell_command("git diff --cached .")

        msg = memo || "workspace change"
        run_shell_command(%(git commit -m "#{msg}"), allow_unsafe_shell_command: true)

        [head_sha, diff]
      end

      def reset(sha)
        run_shell_command("git reset --hard #{sha}")
      end

      def clean
        run_shell_command("git clean -fx .")
      end

      def run_shell_command(*args, **kwargs)
        Dir.chdir(path) { SharedHelpers.run_shell_command(*args, **kwargs) }
      end

      def debug(message)
        Dependabot.logger.debug("[workspace] #{message}")
      end
    end
  end
end
