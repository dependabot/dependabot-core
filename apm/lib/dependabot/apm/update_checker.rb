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

      # Base `vulnerable?` only inspects the merged dependency's single version,
      # which DependencySet collapses to the LOWEST pinned ref. A merged APM
      # dependency can pin several refs, and an advisory may affect only a higher
      # one (e.g. declarations `v1.0.0` and `v2.0.0` with an advisory on
      # `>= 2.0.0, < 2.1.0`): base would see `v1.0.0`, report not-vulnerable, and
      # the security update would be skipped upstream, leaving the vulnerable
      # `v2.0.0` declaration unfixed. So also treat the dependency as vulnerable
      # when ANY requirement's own ref version is affected.
      sig { returns(T::Boolean) }
      def vulnerable?
        super || requirement_versions.any? { |version| ref_vulnerable?(version) }
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
          # a tag family (e.g. `review--v1.0.0` and `review-v1.0.0`). Resolve each
          # requirement independently -- within its own family and above its own
          # pinned version -- so a declaration is only ever bumped within its own
          # family, and a higher declaration is never rewritten down to a lower
          # family's tag or a lower requirement's security fix.
          new_tag = resolved_tag_for_requirement(source, ref_version)&.tag
          next req unless new_tag

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

        # A merged dependency can hold several ref families (e.g. `review--v*`
        # and `review-v*`). Report the highest tag reachable by ANY requirement,
        # each resolved within its own family and above its own pinned version,
        # so the base `can_update?` isn't short-circuited when only a non-first
        # family has a newer tag.
        semver_requirement_checkers.filter_map do |ref_version, checker|
          tag_version = latest_version_tag(checker)&.version
          tag_version if tag_version && Version.new(ref_version) < tag_version
        end.max || dependency.version
      end

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_lowest_security_fix_version
        return unless git_commit_checker.git_dependency?
        return unless git_commit_checker.pinned_ref_looks_like_version?

        # Lowest security fix across the requirement families that are ACTUALLY
        # vulnerable, each filtered above its OWN pinned version so a higher
        # declaration's fix (e.g. the `v2.1.0` for a `v2.0.0` pin) isn't masked
        # by a lower family's `v1.1.0`, and a declaration that isn't itself
        # affected never contributes a spurious fix.
        semver_requirement_checkers.filter_map do |ref_version, checker|
          parsed = Version.new(ref_version)
          next unless ref_vulnerable?(parsed)

          lowest_security_fix_tag(checker, parsed)&.version
        end.min
      end

      # The tag a single requirement should move to: resolved within that
      # requirement's own ref family (via a checker scoped to its ref) and, for
      # security fixes, filtered strictly above that requirement's own pinned
      # version. Returns nil when there is no strictly-higher tag, so a
      # requirement is never downgraded -- a lower selected tag (a security fix,
      # or a latest capped by an ignore rule) must leave an already-higher
      # declaration untouched.
      sig do
        params(source: Dependabot::DependencyRequirement::ObjectHash, ref_version: String)
          .returns(T.nilable(Dependabot::GitTagDetails))
      end
      def resolved_tag_for_requirement(source, ref_version)
        checker = git_commit_checker_for(source)
        return unless checker.pinned_ref_looks_like_version?

        parsed = Version.new(ref_version)
        tag =
          if ref_vulnerable?(parsed)
            # This declaration is itself vulnerable: move it to the lowest fix
            # strictly above its OWN pinned version.
            lowest_security_fix_tag(checker, parsed)
          elsif security_advisories.any?
            # A security update is in progress but this declaration isn't
            # affected -- leave it untouched even when a sibling declaration is
            # being fixed, so security updates stay minimal.
            return
          else
            latest_version_tag(checker)
          end
        tag_version = tag&.version
        return unless tag_version
        return if parsed >= tag_version

        tag
      end

      # Each git-semver-pinned requirement paired with a checker scoped to its
      # own ref (all sharing one remote fetch via shared_git_metadata_fetcher).
      # Drives both the per-requirement rewriting in updated_requirements and the
      # cross-family latest/security-fix version reporting that gates can_update?.
      sig { returns(T::Array[[String, Dependabot::GitCommitChecker]]) }
      def semver_requirement_checkers
        dependency.requirements.filter_map do |req|
          source = req.source_hash
          current_ref = req.source_string("ref")
          ref_version = current_ref && Version.semver_from_ref(current_ref, dependency_name: dependency.name)
          next unless source && ref_version

          [ref_version, git_commit_checker_for(source)]
        end
      end

      # The parsed SemVer core of every requirement pinned to a version tag
      # (plain or package-scoped, e.g. `review--v1.0.0`). Branch- and SHA-pinned
      # requirements carry no comparable version and are skipped. Used to test
      # each declaration's own ref against the advisories.
      sig { returns(T::Array[Dependabot::Version]) }
      def requirement_versions
        dependency.requirements.filter_map do |req|
          current_ref = req.source_string("ref")
          ref_version = current_ref && Version.semver_from_ref(current_ref, dependency_name: dependency.name)
          ref_version && Version.new(ref_version)
        end
      end

      sig { params(version: Gem::Version).returns(T::Boolean) }
      def ref_vulnerable?(version)
        security_advisories.any? { |advisory| advisory.vulnerable?(version) }
      end

      sig { params(checker: Dependabot::GitCommitChecker).returns(T.nilable(Dependabot::GitTagDetails)) }
      def latest_version_tag(checker = git_commit_checker)
        return unless checker.git_dependency?
        return unless checker.pinned_ref_looks_like_version?

        checker.local_tag_for_latest_version(update_cooldown)
      end

      sig do
        params(checker: Dependabot::GitCommitChecker, min_version: T.nilable(Gem::Version))
          .returns(T.nilable(Dependabot::GitTagDetails))
      end
      def lowest_security_fix_tag(checker = git_commit_checker, min_version = current_version)
        return unless checker.git_dependency?
        return unless checker.pinned_ref_looks_like_version?

        allowed_tags = checker.local_tags_for_allowed_versions
        fixed_tags = Dependabot::UpdateCheckers::VersionFilters
                     .filter_vulnerable_versions(allowed_tags, security_advisories)
        # Never downgrade: an advisory that only affects the current line (e.g.
        # ">= 2.0.0, < 2.0.1" while on 2.0.0) must not resolve to an older,
        # unaffected tag. For a merged dependency, filter relative to the
        # requirement's own pinned version (min_version) so each declaration gets
        # the lowest fix above ITS OWN version -- a `v2.0.0` pin must reach its
        # `v2.1.0` fix rather than the dependency-wide lowest `v1.1.0`.
        higher_than(fixed_tags, min_version).min_by { |t| T.must(t.version) }
      end

      # Keeps only tags that carry a version and sit strictly above the given
      # version (a requirement's own pinned version, or the dependency's current
      # version when resolving a single declaration).
      sig do
        params(tags: T::Array[Dependabot::GitTagDetails], version: T.nilable(Gem::Version))
          .returns(T::Array[Dependabot::GitTagDetails])
      end
      def higher_than(tags, version)
        versioned = tags.select(&:version)
        return versioned unless version

        versioned.select { |t| T.must(t.version) > version }
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
