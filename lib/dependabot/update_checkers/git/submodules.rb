# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"

module Dependabot
  module UpdateCheckers
    module Git
      class Submodules < Dependabot::UpdateCheckers::Base
        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          # Resolvability isn't an issue for submodules.
          latest_version
        end

        def latest_version_resolvable_with_full_unlock?
          # Always true, since we're not doing resolution
          !latest_resolvable_version.nil?
        end

        def updated_requirements
          # Submodule requirements are the URL and branch to use for the
          # submodule. We never want to update either.
          dependency.requirements
        end

        private

        def fetch_latest_version
          git_commit_checker = GitCommitChecker.new(
            dependency: dependency,
            github_access_token: github_access_token
          )

          git_commit_checker.head_commit_for_current_branch
        end

        def github_access_token
          credentials.
            find { |cred| cred["host"] == "github.com" }.
            fetch("password")
        end
      end
    end
  end
end
