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
        SharedHelpers.run_shell_command("git diff --patch #{@initial_head_sha}..")
      end

      protected

      def capture_change(memo = nil)
        changed_files = SharedHelpers.run_shell_command("git status --short").strip
        return nil if changed_files.empty?

        sha, diff = commit(memo)
        ChangeAttempt.new(self, id: sha, memo: memo, diff: diff)
      end

      def capture_failed_change_attempt(memo = nil, error = nil)
        changed_files =
          SharedHelpers.run_shell_command("git status --untracked-files=all --ignored=matching --short").strip
        return nil if changed_files.nil? && error.nil?

        sha, diff = stash(memo)
        ChangeAttempt.new(self, id: sha, memo: memo, diff: diff, error: error)
      end

      def reset!
        failed_change_attempts.each do |c|
          SharedHelpers.run_shell_command("git stash drop #{c.id}")
        end
        @change_attempts = []

        reset(@initial_head_sha)
        clean

        nil
      end

      private

      def head_sha
        SharedHelpers.run_shell_command("git rev-parse HEAD").strip
      end

      def last_stash_sha
        # SharedHelpers.run_shell_command("git stash list --format=format:%H -n1").strip
        SharedHelpers.run_shell_command("git rev-parse refs/stash").strip
      end

      def stash(memo = nil)
        msg = memo || "workspace change attempt"
        SharedHelpers.run_shell_command(
          %(git stash push --all --include-untracked -m "#{msg}"),
          allow_unsafe_shell_command: true
        )

        sha = last_stash_sha
        diff = SharedHelpers.run_shell_command("git stash show --patch --include-untracked #{sha}")

        [sha, diff]
      end

      def commit(memo = nil)
        SharedHelpers.run_shell_command("git add #{path}")
        diff = SharedHelpers.run_shell_command("git diff --cached")

        msg = memo || "workspace change"
        SharedHelpers.run_shell_command(%(git commit -m "#{msg}"), allow_unsafe_shell_command: true)

        [head_sha, diff]
      end

      def reset(sha)
        SharedHelpers.run_shell_command("git reset #{sha} --hard")
      end

      def clean
        SharedHelpers.run_shell_command("git clean -fx")
      end
    end
  end
end
