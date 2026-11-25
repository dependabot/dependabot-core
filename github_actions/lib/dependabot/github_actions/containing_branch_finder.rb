# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module GithubActions
    module ContainingBranchFinder
      extend T::Sig

      # A missing commit has no containing branch, so callers can handle it like
      # an empty branch lookup without masking unrelated subprocess failures.
      COMMIT_NOT_FOUND_REGEX = /no such commit|malformed object name|bad object|not a valid object name/i

      sig { params(sha: String).returns(T.nilable(String)) }
      def self.find(sha)
        branches_including_ref = SharedHelpers.run_shell_command(
          "git branch --remotes --contains #{sha}",
          fingerprint: "git branch --remotes --contains <sha>"
        ).split("\n").map { |branch| branch.strip.gsub("origin/", "") }
        return if branches_including_ref.empty?

        current_branch = branches_including_ref.find { |branch| branch.start_with?("HEAD -> ") }

        if current_branch
          current_branch.delete_prefix("HEAD -> ")
        elsif branches_including_ref.size > 1
          # Release SHAs often sit on several release and backport branches, so there is no single branch to follow.
          Dependabot.logger.info(
            "Multiple branches include #{sha}, so no branch to follow: #{branches_including_ref.join(', ')}"
          )
          nil
        else
          branches_including_ref.first
        end
      rescue SharedHelpers::HelperSubprocessFailed => e
        raise unless e.message.match?(COMMIT_NOT_FOUND_REGEX)

        nil
      end
    end
  end
end
