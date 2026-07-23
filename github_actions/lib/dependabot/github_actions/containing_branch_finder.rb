# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module GithubActions
    module ContainingBranchFinder
      extend T::Sig

      # A missing commit has no containing branch, so callers can handle it like
      # an empty branch lookup without masking unrelated subprocess failures.
      COMMIT_NOT_FOUND_REGEX = T.let(
        /no such commit|malformed object name|bad object|not a valid object name/i,
        Regexp
      )

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
          raise "Multiple ambiguous branches (#{branches_including_ref.join(', ')}) include #{sha}!"
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
