# frozen_string_literal: true

require "dependabot/git_commit_checker"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn < Dependabot::UpdateCheckers::Base
        require_relative "npm_and_yarn/requirements_updater"
        require_relative "npm_and_yarn/library_detector"
        require_relative "npm_and_yarn/version_resolver"

        def latest_version
          return latest_version_for_git_dependency if git_dependency?
          latest_version_details&.fetch(:version)
        end

        def latest_resolvable_version
          # Javascript doesn't have the concept of version conflicts, so the
          # latest version is always resolvable.
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          if git_dependency?
            return latest_resolvable_version_with_no_unlock_for_git_dependency
          end

          version_resolver.latest_resolvable_version_with_no_unlock
        end

        def updated_requirements
          @updated_requirements ||=
            RequirementsUpdater.new(
              requirements: dependency.requirements,
              updated_source: updated_source,
              latest_version:
                latest_version_details&.fetch(:version, nil)&.to_s,
              latest_resolvable_version:
                latest_version_details&.fetch(:version, nil)&.to_s,
              update_strategy: requirements_update_strategy
            ).updated_requirements
        end

        def requirements_update_strategy
          # If passed in as an option (in the base class) honour that option
          if @requirements_update_strategy
            return @requirements_update_strategy.to_sym
          end

          # Otherwise, widen ranges for libraries and bump versions for apps
          library? ? :widen_ranges : :bump_versions
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for JS (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def latest_resolvable_version_with_no_unlock_for_git_dependency
          reqs = dependency.requirements.map do |r|
            next if r.fetch(:requirement).nil?
            requirement_class.requirements_array(r.fetch(:requirement))
          end.compact

          return dependency.version if git_commit_checker.pinned?

          # TODO: Really we should get a tag that satisfies the semver req
          return dependency.version if reqs.any?

          git_commit_checker.head_commit_for_current_branch
        end

        def latest_version_for_git_dependency
          latest_release = version_resolver.latest_version_details_from_registry

          # If there's been a release that includes the current pinned ref or
          # that the current branch is behind, we switch to that release.
          if git_branch_or_ref_in_release?(latest_release&.fetch(:version))
            return latest_release.fetch(:version)
          end

          latest_git_version_details[:sha]
        end

        def should_switch_source_from_git_to_registry?
          return false unless git_dependency?
          return false if latest_version_for_git_dependency.nil?
          version_class.correct?(latest_version_for_git_dependency)
        end

        def git_branch_or_ref_in_release?(release)
          return false unless release
          git_commit_checker.branch_or_ref_in_release?(release)
        end

        def latest_version_details
          @latest_version_details ||=
            if git_dependency? && !should_switch_source_from_git_to_registry?
              latest_git_version_details
            else
              version_resolver.latest_version_details_from_registry
            end
        end

        def version_resolver
          @version_resolver ||=
            VersionResolver.new(
              dependency: dependency,
              credentials: credentials,
              dependency_files: dependency_files,
              ignored_versions: ignored_versions
            )
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def latest_git_version_details
          semver_req =
            dependency.requirements.
            find { |req| req.dig(:source, :type) == "git" }&.
            fetch(:requirement)

          # If there was a semver requirement provided or the dependency was
          # pinned to a version, look for the latest tag
          if semver_req || git_commit_checker.pinned_ref_looks_like_version?
            latest_tag = git_commit_checker.local_tag_for_latest_version
            return {
              sha: latest_tag&.fetch(:commit_sha),
              version: latest_tag&.fetch(:tag)&.gsub(/^[^\d]*/, "")
            }
          end

          # Otherwise, if the gem isn't pinned, the latest version is just the
          # latest commit for the specified branch.
          unless git_commit_checker.pinned?
            return { sha: git_commit_checker.head_commit_for_current_branch }
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          { sha: dependency.version }
        end

        def updated_source
          # Never need to update source, unless a git_dependency
          return dependency_source_details unless git_dependency?

          # Source becomes `nil` if switching to default rubygems
          return nil if should_switch_source_from_git_to_registry?

          # Update the git tag if updating a pinned version
          if git_commit_checker.pinned_ref_looks_like_version? &&
             !git_commit_checker.local_tag_for_latest_version.nil?
            new_tag = git_commit_checker.local_tag_for_latest_version
            return dependency_source_details.merge(ref: new_tag.fetch(:tag))
          end

          # Otherwise return the original source
          dependency_source_details
        end

        def library?
          return true unless dependency.version
          return true if dependency_files.any? { |f| f.name == "lerna.json" }

          @library =
            LibraryDetector.new(package_json_file: package_json).library?
        end

        def dependency_source_details
          sources =
            dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

          sources.first
        end

        def package_json
          @package_json ||=
            dependency_files.find { |f| f.name == "package.json" }
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              credentials: credentials
            )
        end
      end
    end
  end
end
