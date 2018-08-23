# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"

module Dependabot
  module UpdateCheckers
    module Terraform
      class Terraform < Dependabot::UpdateCheckers::Base
        def latest_version
          return latest_version_for_git_dependency if git_dependency?
          # TODO: Handle registry dependencies, too
        end

        def latest_resolvable_version
          # No concept of resolvability for terraform modules (that we're aware
          # of - there may be in future).
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          # Irrelevant, since Terraform doesn't have a lockfile
          nil
        end

        def updated_requirements
          dependency.requirements.map do |req|
            next req unless req.dig(:source, :type) == "git"
            next req unless req.dig(:source, :ref)
            next req unless latest_version
            next req if latest_version.to_s.match?(/^[0-9a-f]{40}$/)
            req.merge(source: req[:source].merge(ref: latest_version))
          end
        end

        def requirements_unlocked_or_can_be?
          # If the requirement comes from a proxy URL then there's no way for
          # us to update it
          !proxy_requirement?
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't relevant for Terraform files
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def latest_version_for_git_dependency
          # If the module isn't pinned then there's nothing for us to update
          # (since there's no lockfile to update the version in). We still
          # return the latest commit for the given branch, in order to keep
          # this method consistent
          unless git_commit_checker.pinned?
            return git_commit_checker.head_commit_for_current_branch
          end

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag. Because we don't have a lockfile, the
          # latest version is the tag itself.
          if git_commit_checker.pinned_ref_looks_like_version?
            latest_tag = git_commit_checker.local_tag_for_latest_version
            return latest_tag&.fetch(:tag) || dependency.version
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          dependency.version
        end

        def proxy_requirement?
          dependencies.requirements.any? do |req|
            req.fetch(:source)&.fetch(:proxy_url, nil)
          end
        end

        def ignore_reqs
          ignored_versions.map { |req| requirement_class.new(req.split(",")) }
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              credentials: credentials,
              ignored_versions: ignored_versions
            )
        end
      end
    end
  end
end
