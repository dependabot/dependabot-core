# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/git_commit_checker"
require "dependabot/git_metadata_fetcher"
require "dependabot/git_tag_details"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
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

      # APM packages have no GitHub Advisory Database coverage, so Dependabot
      # never supplies security advisories for them and the security-update flow
      # (gated on `vulnerable?`, which is false without advisories) never runs.
      # We have no visibility into whether APM security updates will be offered
      # in the future; if they are, this needs a real implementation. The base
      # declares it abstract, so it is stubbed to nil to satisfy the contract
      # rather than carrying unreachable resolution logic.
      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_security_fix_version
        nil
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_resolvable_security_fix_version
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
          # a tag family (e.g. `review--v1.0.0` and `review-v1.0.0`). Resolve each
          # requirement independently -- within its own family and above its own
          # pinned version -- so a declaration is only ever bumped within its own
          # family, and a higher declaration is never rewritten down to a lower
          # family's tag.
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

      # `latest_version` deliberately reports the MAX tag reachable by ANY family
      # so the base `can_update?` gate still fires when only a higher family can
      # move. But `DependencySet` defines a merged dependency's version as its
      # LOWEST pin, and `updated_requirements` can leave families on different
      # tags (e.g. `review-v1.4.0` alongside `review--v1.5.0`). Deriving the
      # resulting version from `preferred_resolvable_version` (the max) would
      # report a `1.5.0` update while the merged dependency is really `1.4.0`,
      # desyncing the reported version (and its update type / PR metadata) from
      # the rewritten requirements. Derive it from the post-update refs with the
      # same lowest-pin rule instead, keeping the update gate and the reported
      # version separate.
      sig { returns(Dependabot::Dependency) }
      def updated_dependency_with_own_req_unlock
        new_requirements = updated_requirements
        new_version = pinned_versions(new_requirements).min

        Dependabot::Dependency.new(
          name: dependency.name,
          version: new_version || dependency.version,
          requirements: new_requirements,
          previous_version: dependency.version,
          previous_requirements: dependency.requirements,
          package_manager: dependency.package_manager,
          metadata: dependency.metadata,
          subdependency_metadata: dependency.subdependency_metadata
        )
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

      # The tag a single requirement should move to: the latest tag resolved
      # within that requirement's own ref family (via a checker scoped to its
      # ref). Returns nil when there is no strictly-higher tag, so a requirement
      # is never downgraded -- a latest capped by an ignore rule must leave an
      # already-higher declaration untouched.
      sig do
        params(source: Dependabot::DependencyRequirement::ObjectHash, ref_version: String)
          .returns(T.nilable(Dependabot::GitTagDetails))
      end
      def resolved_tag_for_requirement(source, ref_version)
        checker = git_commit_checker_for(source, ref_version)
        return unless checker.pinned_ref_looks_like_version?

        parsed = Version.new(ref_version)
        tag = latest_version_tag(checker)
        tag_version = tag&.version
        return unless tag_version
        return if parsed >= tag_version

        tag
      end

      # Each git-semver-pinned requirement paired with a checker scoped to its
      # own ref (all sharing one remote fetch via shared_git_metadata_fetcher).
      # Drives the cross-family latest-version reporting that gates can_update?,
      # so the gate still fires when only a non-first family has a newer tag.
      sig { returns(T::Array[[String, Dependabot::GitCommitChecker]]) }
      def semver_requirement_checkers
        dependency.requirements.filter_map do |req|
          source = req.source_hash
          current_ref = req.source_string("ref")
          ref_version = current_ref && Version.semver_from_ref(current_ref, dependency_name: dependency.name)
          next unless source && ref_version

          [ref_version, git_commit_checker_for(source, ref_version)]
        end
      end

      # The parsed SemVer core of every requirement pinned to a version tag
      # (plain or package-scoped, e.g. `review--v1.0.0`). Branch- and SHA-pinned
      # requirements carry no comparable version and are skipped. Used to derive
      # the merged post-update version (its lowest pin).
      sig { params(requirements: T::Array[Dependabot::DependencyRequirement]).returns(T::Array[Dependabot::Version]) }
      def pinned_versions(requirements)
        requirements.filter_map do |req|
          current_ref = req.source_string("ref")
          ref_version = current_ref && Version.semver_from_ref(current_ref, dependency_name: dependency.name)
          ref_version && Version.new(ref_version)
        end
      end

      sig { params(checker: Dependabot::GitCommitChecker).returns(T.nilable(Dependabot::GitTagDetails)) }
      def latest_version_tag(checker = git_commit_checker)
        return unless checker.git_dependency?
        return unless checker.pinned_ref_looks_like_version?

        checker.local_tag_for_latest_version(update_cooldown)
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
      # tags in that declaration's own family. When `ref_version` is given the
      # checker's dependency version is scoped to this requirement's own pinned
      # ref, so GitCommitChecker#current_version (and therefore cooldown's
      # SemVer-distance classification) reflects THIS declaration rather than the
      # merged dependency's lowest pin -- e.g. a `v2.1.0` candidate for a `v2.0.0`
      # pin stays a minor bump even when a sibling `v1.4.0` pin lowers the merged
      # version to 1.4.0.
      sig do
        params(
          source: Dependabot::DependencyRequirement::ObjectHash,
          ref_version: T.nilable(String)
        ).returns(Dependabot::GitCommitChecker)
      end
      def git_commit_checker_for(source, ref_version = nil)
        scoped_dependency =
          if ref_version
            Dependabot::Dependency.new(
              name: dependency.name,
              version: ref_version,
              requirements: dependency.requirements,
              package_manager: dependency.package_manager,
              metadata: dependency.metadata,
              subdependency_metadata: dependency.subdependency_metadata
            )
          else
            dependency
          end

        Dependabot::Apm::GitCommitChecker.new(
          dependency: scoped_dependency,
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
