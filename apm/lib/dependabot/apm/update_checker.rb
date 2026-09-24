# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/git_commit_checker"
require "dependabot/git_metadata_fetcher"
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
        return dependency.requirements unless git_commit_checker.git_dependency?

        dependency.requirements.map do |req|
          source = req.source_hash
          current_ref = req.source_string("ref")
          # Only rewrite requirements pinned to a semver tag (plain or
          # package-scoped, e.g. `review--v1.0.0`); branch- and SHA-pinned
          # entries are left as-is. Normalise the ref to its SemVer core through
          # the shared APM extractor so scoped tags are recognised and compared.
          ref_version = current_ref && Version.semver_from_ref(current_ref, dependency_name: dependency.name)
          next req unless source && ref_version

          # DependencySet merges repeated declarations of the same package into a
          # single dependency with several requirements whose refs need not share
          # a tag family (e.g. `review--v1.0.0` and `review-v1.0.0`). Resolve the
          # update per requirement source -- each through a checker scoped to that
          # ref, sharing one remote fetch -- so a declaration is only ever bumped
          # within its own tag family instead of being rewritten into the first
          # requirement's family or missing its own newer tag.
          git_tag = updated_git_tag_for(git_commit_checker_for(source))
          new_tag = git_tag&.tag
          next req unless new_tag

          new_version = git_tag.version
          # Never rewrite a requirement whose own ref already sits at or above the
          # resolved tag -- a lower selected tag (a security fix, or a latest
          # capped by an ignore rule) would otherwise downgrade a higher
          # declaration, e.g. a v1.5.0 fix must leave a v2.0.0 entry untouched.
          next req if new_version && Version.new(ref_version) >= new_version

          new_source = source.merge(ref: new_tag)
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

      sig { params(checker: Dependabot::GitCommitChecker).returns(T.nilable(Dependabot::GitTagDetails)) }
      def updated_git_tag_for(checker)
        return unless checker.pinned_ref_looks_like_version?

        vulnerable? ? lowest_security_fix_tag(checker) : latest_version_tag(checker)
      end

      sig { params(checker: Dependabot::GitCommitChecker).returns(T.nilable(Dependabot::GitTagDetails)) }
      def latest_version_tag(checker = git_commit_checker)
        return unless checker.git_dependency?
        return unless checker.pinned_ref_looks_like_version?

        checker.local_tag_for_latest_version(update_cooldown)
      end

      sig { params(checker: Dependabot::GitCommitChecker).returns(T.nilable(Dependabot::GitTagDetails)) }
      def lowest_security_fix_tag(checker = git_commit_checker)
        return unless checker.git_dependency?
        return unless checker.pinned_ref_looks_like_version?

        allowed_tags = checker.local_tags_for_allowed_versions
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
            consider_version_branches_pinned: false,
            git_metadata_fetcher: shared_git_metadata_fetcher
          ),
          T.nilable(Dependabot::GitCommitChecker)
        )
      end

      # A checker scoped to a single requirement's source (its own ref), sharing
      # one remote metadata fetch across every requirement so per-requirement
      # resolution does not re-fetch the upload pack for each declaration. The
      # scoped ref makes the parent's family filtering (`same_prefix?`) select
      # tags in that declaration's own family.
      sig { params(source: Dependabot::DependencyRequirement::ObjectHash).returns(Dependabot::GitCommitChecker) }
      def git_commit_checker_for(source)
        Dependabot::Apm::GitCommitChecker.new(
          dependency: dependency,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          consider_version_branches_pinned: false,
          dependency_source_details: symbolized_source_details(source),
          git_metadata_fetcher: shared_git_metadata_fetcher
        )
      end

      # One metadata fetcher for the dependency's git remote, shared by the main
      # and per-requirement checkers so the upload pack is fetched once. All
      # requirements of a merged dependency share the same clone URL (differing
      # ports/paths keep them as separate dependencies), so a single fetcher is
      # correct. Nil for non-git dependencies, where no fetch is needed.
      sig { returns(T.nilable(Dependabot::GitMetadataFetcher)) }
      def shared_git_metadata_fetcher
        return @shared_git_metadata_fetcher if defined?(@shared_git_metadata_fetcher)

        url = dependency.source_string("url", allowed_types: ["git"])
        @shared_git_metadata_fetcher = T.let(
          url && Dependabot::GitMetadataFetcher.new(url: url, credentials: credentials),
          T.nilable(Dependabot::GitMetadataFetcher)
        )
      end

      # A symbol-keyed source-details hash for GitCommitChecker, holding the git
      # coordinate fields it reads (type/url/ref/branch). Rebuilt explicitly so a
      # requirement's mixed-key source hash conforms to the checker's expected
      # `{Symbol => Object}` shape.
      sig do
        params(source: Dependabot::DependencyRequirement::ObjectHash)
          .returns(T::Hash[Symbol, Object])
      end
      def symbolized_source_details(source)
        details = T.let({}, T::Hash[Symbol, Object])
        %i(type url ref branch).each do |key|
          value = source[key] || source[key.to_s]
          details[key] = value if value.is_a?(String)
        end
        details
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("apm", Dependabot::Apm::UpdateChecker)
