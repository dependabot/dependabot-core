# frozen_string_literal: true

module Dependabot
  module Workspace
    class ChangeAttempt
      attr_reader :diff, :error, :id, :memo, :workspace

      def initialize(workspace, id:, memo:, diff: nil, error: nil)
        @workspace = workspace
        @id = id
        @memo = memo
        @diff = diff
        @error = error
      end

      def success?
        error.nil?
      end

      def error?
        error
      end
    end

    class Base
      attr_reader :change_attempts, :path

      def initialize(path)
        @path = path
        @change_attempts = []
      end

      def changed?
        changes.any?
      end

      def changes
        change_attempts.select(&:success?)
      end

      def failed_change_attempts
        change_attempts.select(&:error?)
      end

      def change(memo = nil)
        change_attempt = nil
        Dir.chdir(path) { yield(path) }
        change_attempt = capture_change(memo)
      rescue StandardError => e
        change_attempt = capture_failed_change_attempt(memo, e)
        raise e
      ensure
        change_attempts << change_attempt unless change_attempt.nil?
        clean
      end

      def to_patch
        ""
      end

      def reset!; end

      protected

      def capture_change(memo = nil); end

      def capture_failed_change_attempt(memo = nil, error = nil); end
    end

    class Git < Base
      attr_reader :initial_head_sha

      def initialize(repo_path, directory = "/")
        super(Pathname.new(File.join(repo_path, directory)).expand_path)
        @initial_head_sha = head_sha
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

      protected

      def capture_change(memo = nil)
        changed_files = run_shell_command("git status --short .").strip
        return nil if changed_files.empty?

        sha, diff = commit(memo)
        ChangeAttempt.new(self, id: sha, memo: memo, diff: diff)
      end

      def capture_failed_change_attempt(memo = nil, error = nil)
        changed_files =
          run_shell_command("git status --untracked-files=all --ignored=matching --short .").strip
        return nil if changed_files.nil? && error.nil?

        sha, diff = stash(memo)
        ChangeAttempt.new(self, id: sha, memo: memo, diff: diff, error: error)
      end

      private

      def head_sha
        run_shell_command("git rev-parse HEAD").strip
      end

      def last_stash_sha
        run_shell_command("git rev-parse refs/stash").strip
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
    end
  end
end
