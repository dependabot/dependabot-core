# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/git_commit_checker"
require "dependabot/git_tag_details"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"
require "dependabot/apm/git_commit_checker"
require "dependabot/apm/requirement"
require "dependabot/apm/version"

module Dependabot
  module Apm
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(
          fetch_latest_version,
          T.nilable(T.any(String, Gem::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # APM dependencies have no resolution graph: each manifest ref is
        # independent, so the latest version is always resolvable.
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version_with_no_unlock
        # Updating an APM dependency always rewrites its manifest requirement,
        # so there is no newer version reachable "without unlocking".
        dependency.version
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_security_fix_version
        @lowest_security_fix_version ||= T.let(
          fetch_lowest_security_fix_version,
          T.nilable(Gem::Version)
        )
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_resolvable_security_fix_version
        # Resolvability isn't a concern for APM, so the lowest resolvable fix is
        # simply the lowest fix.
        lowest_security_fix_version
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        new_tag = updated_git_tag&.tag
        return dependency.requirements unless new_tag

        dependency.requirements.map do |req|
          current_ref = req.source_string("ref")
          # Only rewrite requirements pinned to a semver tag; branch- and
          # SHA-pinned entries are left as-is.
          next req unless current_ref && version_class.correct?(current_ref)

          new_source = T.must(req.source_hash).merge(ref: new_tag)
          Dependabot::DependencyRequirement.create(req.merge(source: new_source))
        end
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # APM has no concept of a full unlock (no transitive resolution).
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def fetch_latest_version
        return dependency.version unless git_commit_checker.git_dependency?

        # Only entries pinned to a semver tag are bumped in the manifest.
        # Branch- and SHA-pinned entries are resolved via the lockfile, which
        # APM regenerates itself, so Dependabot leaves them untouched.
        return dependency.version unless git_commit_checker.pinned_ref_looks_like_version?

        latest_version_tag&.version || dependency.version
      end

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_lowest_security_fix_version
        return unless git_commit_checker.git_dependency?
        return unless git_commit_checker.pinned_ref_looks_like_version?

        lowest_security_fix_tag&.version
      end

      sig { returns(T.nilable(Dependabot::GitTagDetails)) }
      def updated_git_tag
        return @updated_git_tag if defined?(@updated_git_tag)

        @updated_git_tag = T.let(
          vulnerable? ? lowest_security_fix_tag : latest_version_tag,
          T.nilable(Dependabot::GitTagDetails)
        )
      end

      sig { returns(T.nilable(Dependabot::GitTagDetails)) }
      def latest_version_tag
        return unless git_commit_checker.git_dependency?
        return unless git_commit_checker.pinned_ref_looks_like_version?

        git_commit_checker.local_tag_for_latest_version(update_cooldown)
      end

      sig { returns(T.nilable(Dependabot::GitTagDetails)) }
      def lowest_security_fix_tag
        return unless git_commit_checker.git_dependency?
        return unless git_commit_checker.pinned_ref_looks_like_version?

        allowed_tags = git_commit_checker.local_tags_for_allowed_versions
        fixed_tags = Dependabot::UpdateCheckers::VersionFilters
                     .filter_vulnerable_versions(allowed_tags, security_advisories)
        # Never downgrade: an advisory that only affects the current line (e.g.
        # ">= 2.0.0, < 2.0.1" while on 2.0.0) must not resolve to an older,
        # unaffected tag. Match the GitHub Actions finder and drop anything at or
        # below the current version before taking the lowest remaining fix.
        higher_than_current(fixed_tags).min_by { |t| T.must(t.version) }
      end

      # Keeps only tags that carry a version and sit strictly above the version
      # currently pinned in the manifest.
      sig do
        params(tags: T::Array[Dependabot::GitTagDetails])
          .returns(T::Array[Dependabot::GitTagDetails])
      end
      def higher_than_current(tags)
        versioned = tags.select(&:version)
        current = current_version
        return versioned unless current

        versioned.select { |t| T.must(t.version) > current }
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(
          Dependabot::Apm::GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            consider_version_branches_pinned: false
          ),
          T.nilable(Dependabot::GitCommitChecker)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("apm", Dependabot::Apm::UpdateChecker)
