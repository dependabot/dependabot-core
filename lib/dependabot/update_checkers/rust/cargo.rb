# frozen_string_literal: true

require "excon"
require "dependabot/git_commit_checker"
require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Rust
      class Cargo < Dependabot::UpdateCheckers::Base
        require_relative "cargo/requirements_updater"
        require_relative "cargo/version_resolver"
        require_relative "cargo/file_preparer"

        def latest_version
          return if path_dependency?

          @latest_version =
            if git_dependency?
              latest_version_for_git_dependency
            else
              versions = available_versions
              versions.reject!(&:prerelease?) unless wants_prerelease?
              versions.reject! do |v|
                ignore_reqs.any? { |r| r.satisfied_by?(v) }
              end
              versions.max
            end
        end

        def latest_resolvable_version
          return if path_dependency?

          @latest_resolvable_version ||=
            if git_dependency?
              latest_resolvable_version_for_git_dependency
            else
              fetch_latest_resolvable_version(unlock_requirement: true)
            end
        end

        def latest_resolvable_version_with_no_unlock
          return if path_dependency?

          @latest_resolvable_version_with_no_unlock ||=
            if git_dependency?
              latest_resolvable_commit_with_unchanged_git_source
            else
              fetch_latest_resolvable_version(unlock_requirement: false)
            end
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            updated_source: updated_source,
            latest_resolvable_version: latest_resolvable_version&.to_s,
            latest_version: latest_version&.to_s,
            library: library?,
            update_strategy: requirement_update_strategy
          ).updated_requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Rust (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def library?
          # If it has a lockfile, treat it as an application. Otherwise treat it
          # as a library.
          dependency_files.none? { |f| f.name == "Cargo.lock" }
        end

        def requirement_update_strategy
          library? ? :bump_versions_if_needed : :bump_versions
        end

        def latest_version_for_git_dependency
          latest_git_version_sha
        end

        def latest_git_version_sha
          # If the gem isn't pinned, the latest version is just the latest
          # commit for the specified branch.
          unless git_commit_checker.pinned?
            return git_commit_checker.head_commit_for_current_branch
          end

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag. The latest version will then be the SHA
          # of the latest tag that looks like a version.
          if git_commit_checker.pinned_ref_looks_like_version?
            latest_tag = git_commit_checker.local_tag_for_latest_version
            return latest_tag&.fetch(:commit_sha) || dependency.version
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          dependency.version
        end

        def latest_resolvable_version_for_git_dependency
          # If the gem isn't pinned, the latest version is just the latest
          # commit for the specified branch.
          unless git_commit_checker.pinned?
            return latest_resolvable_commit_with_unchanged_git_source
          end

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag. The latest version will then be the SHA
          # of the latest tag that looks like a version.
          if git_commit_checker.pinned_ref_looks_like_version? &&
             latest_git_tag_is_resolvable?
            new_tag = git_commit_checker.local_tag_for_latest_version
            return new_tag.fetch(:commit_sha)
          end

          # If the dependency is pinned then there's nothing we can do.
          dependency.version
        end

        def latest_git_tag_is_resolvable?
          return @git_tag_resolvable if @latest_git_tag_is_resolvable_checked
          @latest_git_tag_is_resolvable_checked = true

          return false if git_commit_checker.local_tag_for_latest_version.nil?
          replacement_tag = git_commit_checker.local_tag_for_latest_version

          prepared_files = FilePreparer.new(
            dependency_files: dependency_files,
            dependency: dependency,
            unlock_requirement: true,
            replacement_git_pin: replacement_tag.fetch(:tag)
          ).prepared_dependency_files

          VersionResolver.new(
            dependency: dependency,
            dependency_files: prepared_files,
            credentials: credentials
          ).latest_resolvable_version
          @git_tag_resolvable = true
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise error unless error.message.include?("versions conflict")
          @git_tag_resolvable = false
        end

        def latest_resolvable_commit_with_unchanged_git_source
          fetch_latest_resolvable_version(unlock_requirement: false)
        rescue SharedHelpers::HelperSubprocessFailed => error
          # Resolution may fail, as Cargo updates straight to the tip of the
          # branch. Just return `nil` if it does (so no update).
          return if error.message.include?("versions conflict")
          raise error
        end

        def fetch_latest_resolvable_version(unlock_requirement:)
          prepared_files = FilePreparer.new(
            dependency_files: dependency_files,
            dependency: dependency,
            unlock_requirement: unlock_requirement,
            latest_allowable_version: latest_version
          ).prepared_dependency_files

          VersionResolver.new(
            dependency: dependency,
            dependency_files: prepared_files,
            credentials: credentials
          ).latest_resolvable_version
        end

        def updated_source
          # Never need to update source, unless a git_dependency
          return dependency_source_details unless git_dependency?

          # Update the git tag if updating a pinned version
          if git_commit_checker.pinned_ref_looks_like_version? &&
             latest_git_tag_is_resolvable?
            new_tag = git_commit_checker.local_tag_for_latest_version
            return dependency_source_details.merge(ref: new_tag.fetch(:tag))
          end

          # Otherwise return the original source
          dependency_source_details
        end

        def dependency_source_details
          sources =
            dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

          sources.first
        end

        def wants_prerelease?
          if dependency.version &&
             version_class.new(dependency.version).prerelease?
            return true
          end

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.match?(/[A-Za-z]/) }
          end
        end

        def available_versions
          crates_listing.
            fetch("versions", []).
            reject { |v| v["yanked"] }.
            map { |v| version_class.new(v.fetch("num")) }
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def path_dependency?
          sources = dependency.requirements.
                    map { |r| r.fetch(:source) }.uniq.compact

          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1
          sources.first&.fetch(:type) == "path"
        end

        def ignore_reqs
          ignored_versions.map { |req| requirement_class.new(req.split(",")) }
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              credentials: credentials
            )
        end

        def crates_listing
          return @crates_listing unless @crates_listing.nil?

          response = Excon.get(
            "https://crates.io/api/v1/crates/#{dependency.name}",
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          @crates_listing = JSON.parse(response.body)
        end
      end
    end
  end
end
