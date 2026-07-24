# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/containing_branch_finder"
require "dependabot/github_actions/lockfile/reader"
require "dependabot/github_actions/requirement"
require "dependabot/github_actions/version"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module GithubActions
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      GitSource = T.type_alias { T::Hash[Symbol, String] }

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(
          T.must(latest_version_finder).latest_release_version,
          T.nilable(T.any(String, Gem::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # Resolvability isn't an issue for GitHub Actions.
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        # No concept of "unlocking" for GitHub Actions (since no lockfile)
        dependency.version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        # Resolvability isn't an issue for GitHub Actions.
        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        @lowest_security_fix_version ||= T.let(
          T.must(latest_version_finder).lowest_security_fix_release&.fetch(:version),
          T.nilable(Dependabot::Version)
        )
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        updated_reqs = dependency.requirements.map do |req|
          source = T.cast(req.source, GitSource)
          updated = updated_ref(source, onboarded: onboarded_requirement?(req))
          next req unless updated

          current = source[:ref]

          # Maintain a short git hash only if it matches the latest
          if req[:type] == "git" &&
             git_commit_checker.ref_looks_like_commit_sha?(updated) &&
             git_commit_checker.ref_looks_like_commit_sha?(T.must(current)) &&
             updated.start_with?(T.must(current))
            next req
          end

          new_source = source.merge(ref: updated)
          req.merge(source: new_source)
        end
        wrap_requirements(updated_reqs)
      end

      private

      sig { params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def numeric_version_can_update?(requirements_to_unlock:)
        return true if super
        return false unless requirements_to_unlock == :own

        dependency.requirements.zip(updated_requirements).any? do |current, updated|
          onboarded_requirement?(current) && current != updated
        end
      end

      # A requirement is "onboarded" when the repo carries an `actions.lock` that is
      # authoritative for the requirement's workflow. Only onboarded requirements get
      # per-source precision selection; everything else flows through the combined
      # finder exactly as before, so non-onboarded repos see byte-identical behavior.
      sig { params(req: Dependabot::DependencyRequirement).returns(T::Boolean) }
      def onboarded_requirement?(req)
        reader = lockfile_reader
        return false unless reader

        file = dependency_files.find { |f| f.name == req.file }
        return false unless file

        reader.onboarded?(file.path.delete_prefix("/"))
      end

      sig { returns(T.nilable(Dependabot::GithubActions::Lockfile::Reader)) }
      def lockfile_reader
        return @lockfile_reader if defined?(@lockfile_reader)

        @lockfile_reader = T.let(
          Dependabot::GithubActions::Lockfile::Reader.from_files(dependency_files),
          T.nilable(Dependabot::GithubActions::Lockfile::Reader)
        )
      end

      sig { returns(T.nilable(Dependabot::GithubActions::UpdateChecker::LatestVersionFinder)) }
      def latest_version_finder
        @latest_version_finder ||=
          T.let(
            build_latest_version_finder(dependency),
            T.nilable(Dependabot::GithubActions::UpdateChecker::LatestVersionFinder)
          )
      end

      # A finder scoped to a single requirement's source ref, so version selection
      # precision-matches THAT ref (e.g. `v4.3.1` → latest 3-segment tag) instead of
      # the combined dependency version (the lower of all refs, which flattens every
      # requirement to the coarsest precision). Cached per ref so repeated refs share
      # one underlying clone. Falls back to the combined finder for sources whose ref
      # is not a version (SHA / branch), where precision has no meaning.
      sig { params(source: T.nilable(GitSource)).returns(LatestVersionFinder) }
      def latest_version_finder_for(source)
        ref = source&.fetch(:ref, nil)
        return T.must(latest_version_finder) unless ref && version_class.correct?(ref)

        @latest_version_finder_for ||= T.let({}, T.nilable(T::Hash[String, LatestVersionFinder]))
        @latest_version_finder_for[ref] ||= build_latest_version_finder(per_source_dependency(source, ref))
      end

      sig { params(dep: Dependabot::Dependency).returns(LatestVersionFinder) }
      def build_latest_version_finder(dep)
        LatestVersionFinder.new(
          dependency: dep,
          credentials: credentials,
          dependency_files: dependency_files,
          security_advisories: security_advisories,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          cooldown_options: update_cooldown
        )
      end

      # A synthetic single-requirement dependency whose version mirrors the precision
      # of `source[:ref]`. The downstream precision machinery keys entirely off
      # `dependency.version`, so this is what makes per-source precision selection work
      # without touching the shared combined dependency reported up to the rest of the
      # update.
      sig do
        params(source: GitSource, ref: String)
          .returns(Dependabot::Dependency)
      end
      def per_source_dependency(source, ref)
        Dependabot::Dependency.new(
          name: dependency.name,
          version: version_class.new(ref).to_s,
          requirements: [{ requirement: nil, groups: [], source: source, file: nil, metadata: {} }],
          package_manager: dependency.package_manager
        )
      end

      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      def active_advisories
        security_advisories.select do |advisory|
          version = git_commit_checker.most_specific_tag_equivalent_to_pinned_ref
          version.nil? ? false : advisory.vulnerable?(version_class.new(version))
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for GitHub Actions
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T.nilable(String)) }
      def latest_commit_for_pinned_ref
        @latest_commit_for_pinned_ref ||= T.let(
          begin
            head_commit_for_ref_sha = git_commit_checker.head_commit_for_pinned_ref
            if head_commit_for_ref_sha
              head_commit_for_ref_sha
            else
              url = git_commit_checker.dependency_source_details&.url
              source = T.must(Source.from_url(url))

              SharedHelpers.in_a_temporary_directory(File.dirname(source.repo)) do |temp_dir|
                repo_contents_path = File.join(temp_dir, File.basename(source.repo))

                SharedHelpers.run_shell_command("git clone --no-recurse-submodules #{url} #{repo_contents_path}")

                Dir.chdir(repo_contents_path) do
                  ref_branch = ContainingBranchFinder.find(
                    T.must(git_commit_checker.dependency_source_details&.ref)
                  )
                  git_commit_checker.head_commit_for_local_branch(ref_branch) if ref_branch
                end
              end
            end
          end,
          T.nilable(String)
        )
      end

      sig do
        params(source: T.nilable(GitSource), onboarded: T::Boolean)
          .returns(T.nilable(String))
      end
      def updated_ref(source, onboarded: false)
        # TODO: Support Docker sources
        return unless git_commit_checker.git_dependency?

        finder = onboarded ? latest_version_finder_for(source) : T.must(latest_version_finder)

        if vulnerable? && (new_tag = finder.lowest_security_fix_release)
          return new_tag.fetch(:tag)
        end

        source_git_commit_checker = git_helper.git_commit_checker_for(source)

        # Return the git tag if updating a pinned version
        if source_git_commit_checker.pinned_ref_looks_like_version? &&
           (new_tag = finder.latest_version_tag_respecting_cooldown)
          return new_tag.fetch(:tag)
        end

        # Return the pinned git commit if one is available
        if source_git_commit_checker.pinned_ref_looks_like_commit_sha? &&
           (new_commit_sha = latest_commit_sha(source_git_commit_checker, finder))
          return new_commit_sha
        end

        # Otherwise we can't update the ref
        nil
      end

      sig do
        params(source_checker: Dependabot::GitCommitChecker, finder: LatestVersionFinder)
          .returns(T.nilable(String))
      end
      def latest_commit_sha(source_checker, finder)
        latest_tag = finder.latest_version_tag
        return unless latest_tag

        if source_checker.local_tag_for_pinned_sha
          new_tag = finder.latest_version_tag_respecting_cooldown
          new_tag&.fetch(:commit_sha)
        else
          # Keep SHA rewrites aligned with the checker decision (including cooldown filtering).
          latest = finder.latest_release_version
          latest.is_a?(String) ? latest : latest_commit_for_pinned_ref
        end
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(git_helper.git_commit_checker, T.nilable(Dependabot::GitCommitChecker))
      end

      sig { returns(Dependabot::GithubActions::Helpers::Githelper) }
      def git_helper
        Helpers::Githelper.new(
          dependency: dependency,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          consider_version_branches_pinned: false,
          dependency_source_details: nil
        )
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("github_actions", Dependabot::GithubActions::UpdateChecker)
