# typed: strict
# frozen_string_literal: true

require "dependabot/bundler/file_updater/requirement_replacer"
require "dependabot/bundler/version"
require "dependabot/git_commit_checker"
require "dependabot/requirements_update_strategy"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Bundler
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/force_updater"
      require_relative "update_checker/file_preparer"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"
      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/conflicting_dependency_resolver"
      extend T::Sig

      sig { override.returns(T.nilable(T.any(String, Dependabot::Bundler::Version))) }
      def latest_version
        return latest_version_for_git_dependency if git_dependency?

        latest_version_details&.fetch(:version)
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Bundler::Version))) }
      def latest_resolvable_version
        return latest_resolvable_version_for_git_dependency if git_dependency?

        latest_resolvable_version_details&.fetch(:version)
      end

      sig { override.returns(T.nilable(Dependabot::Bundler::Version)) }
      def lowest_security_fix_version
        T.cast(
          latest_version_finder(remove_git_source: false).lowest_security_fix_version,
          T.nilable(Dependabot::Bundler::Version)
        )
      end

      sig { override.returns(T.nilable(Dependabot::Bundler::Version)) }
      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?
        return T.cast(latest_resolvable_version, T.nilable(Dependabot::Bundler::Version)) if git_dependency?

        lowest_fix =
          latest_version_finder(remove_git_source: false)
          .lowest_security_fix_version
        return unless lowest_fix && resolvable?(T.cast(lowest_fix, Dependabot::Bundler::Version))

        T.cast(lowest_fix, Dependabot::Bundler::Version)
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Bundler::Version))) }
      def latest_resolvable_version_with_no_unlock
        current_ver = dependency.version
        return current_ver if git_dependency? && git_commit_checker.pinned?

        @latest_resolvable_version_detail_with_no_unlock = T.let(
          @latest_resolvable_version_detail_with_no_unlock,
          T.nilable(T::Hash[Symbol, T.untyped])
        )

        @latest_resolvable_version_detail_with_no_unlock ||=
          version_resolver(remove_git_source: false, unlock_requirement: false)
          .latest_resolvable_version_details

        if git_dependency?
          @latest_resolvable_version_detail_with_no_unlock&.fetch(:commit_sha)
        else
          @latest_resolvable_version_detail_with_no_unlock&.fetch(:version)
        end
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        latest_version_for_req_updater = latest_version_details&.fetch(:version)&.to_s
        latest_resolvable_version_for_req_updater = preferred_resolvable_version_details&.fetch(:version)&.to_s

        RequirementsUpdater.new(
          requirements: dependency.requirements,
          update_strategy: T.must(requirements_update_strategy),
          updated_source: updated_source,
          latest_version: latest_version_for_req_updater,
          latest_resolvable_version: latest_resolvable_version_for_req_updater
        ).updated_requirements
      end

      sig { returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        return true if requirements_unlocked?
        return false if T.must(requirements_update_strategy).lockfile_only?

        dependency.specific_requirements
                  .all? do |req|
          file = T.must(dependency_files.find { |f| f.name == req.fetch(:file) })
          updated = FileUpdater::RequirementReplacer.new(
            dependency: dependency,
            file_type: file.name.end_with?("gemspec") ? :gemspec : :gemfile,
            updated_requirement: "whatever"
          ).rewrite(file.content)

          updated != file.content
        end
      end

      sig { returns(T.nilable(Dependabot::RequirementsUpdateStrategy)) }
      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        return @requirements_update_strategy if @requirements_update_strategy

        # Otherwise, widen ranges for libraries and bump versions for apps
        if dependency.version.nil?
          RequirementsUpdateStrategy::BumpVersionsIfNecessary
        else
          RequirementsUpdateStrategy::BumpVersions
        end
      end

      sig { override.returns(T::Array[T::Hash[String, String]]) }
      def conflicting_dependencies
        ConflictingDependencyResolver.new(
          dependency_files: dependency_files,
          repo_contents_path: repo_contents_path,
          credentials: credentials,
          options: options
        ).conflicting_dependencies(
          dependency: dependency,
          target_version: lowest_security_fix_version.to_s # Convert Version to String
        )
      end

      private

      sig { returns(T::Boolean) }
      def requirements_unlocked?
        dependency.specific_requirements.none?
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        return false unless latest_version
        return false if version_resolver(remove_git_source: false).latest_allowable_version_incompatible_with_ruby?

        updated_dependencies = force_updater.updated_dependencies

        updated_dependencies.none? do |dep|
          old_version = dep.previous_version
          next unless Dependabot::Bundler::Version.correct?(old_version)
          next if Dependabot::Bundler::Version.new(old_version).prerelease?

          Dependabot::Bundler::Version.new(dep.version).prerelease?
        end
      rescue Dependabot::DependencyFileNotResolvable
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        force_updater.updated_dependencies
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def preferred_resolvable_version_details
        return { version: lowest_resolvable_security_fix_version } if vulnerable?

        latest_resolvable_version_details
      end

      sig { returns(T::Boolean) }
      def git_dependency?
        git_commit_checker.git_dependency?
      end

      sig { params(version: Dependabot::Bundler::Version).returns(T.untyped) }
      def resolvable?(version)
        @resolvable ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
        return @resolvable[version] if @resolvable.key?(version)

        @resolvable[version] =
          begin
            ForceUpdater.new(
              dependency: dependency,
              dependency_files: dependency_files,
              repo_contents_path: repo_contents_path,
              credentials: credentials,
              target_version: version,
              requirements_update_strategy: T.must(requirements_update_strategy),
              update_multiple_dependencies: false,
              options: options
            ).updated_dependencies
            true
          rescue Dependabot::DependencyFileNotResolvable
            false
          end
      end

      sig { params(tag: T.nilable(String)).returns(T.untyped) }
      def git_tag_resolvable?(tag)
        @git_tag_resolvable ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
        return @git_tag_resolvable[tag] if @git_tag_resolvable.key?(tag)

        @git_tag_resolvable[tag] =
          begin
            VersionResolver.new(
              dependency: dependency,
              unprepared_dependency_files: dependency_files,
              repo_contents_path: repo_contents_path,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: raise_on_ignored,
              replacement_git_pin: tag,
              cooldown_options: update_cooldown,
              options: options
            ).latest_resolvable_version_details
            true
          rescue Dependabot::DependencyFileNotResolvable
            false
          end
      end

      sig { params(remove_git_source: T::Boolean).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def latest_version_details(remove_git_source: false)
        @latest_version_details ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
        @latest_version_details[remove_git_source] ||=
          latest_version_finder(remove_git_source: remove_git_source)
          .latest_version_details
      end

      sig { params(remove_git_source: T::Boolean).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def latest_resolvable_version_details(remove_git_source: false)
        @latest_resolvable_version_details ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
        @latest_resolvable_version_details[remove_git_source] ||=
          version_resolver(remove_git_source: remove_git_source)
          .latest_resolvable_version_details
      end

      sig { returns(T.nilable(T.any(String, Dependabot::Bundler::Version))) }
      def latest_version_for_git_dependency
        latest_release =
          latest_version_details(remove_git_source: true)
          &.fetch(:version)

        # If there's been a release that includes the current pinned ref or
        # that the current branch is behind, we switch to that release.
        return latest_release if git_branch_or_ref_in_release?(latest_release)

        # Otherwise, if the gem isn't pinned, the latest version is just the
        # latest commit for the specified branch.
        return git_commit_checker.head_commit_for_current_branch unless git_commit_checker.pinned?

        # If the dependency is pinned to a tag that looks like a version then
        # we want to update that tag. The latest version will then be the SHA
        # of the latest tag that looks like a version.
        if git_commit_checker.pinned_ref_looks_like_version?
          latest_tag = git_commit_checker.local_tag_for_latest_version
          return latest_tag&.fetch(:tag_sha) || dependency.version
        end

        # If the dependency is pinned to a tag that doesn't look like a
        # version then there's nothing we can do.
        dependency.version
      end

      sig { returns(T.any(String, T.nilable(Dependabot::Bundler::Version))) }
      def latest_resolvable_version_for_git_dependency
        latest_release = latest_resolvable_version_without_git_source

        # If there's a resolvable release that includes the current pinned
        # ref or that the current branch is behind, we switch to that release.
        return latest_release if git_branch_or_ref_in_release?(latest_release)

        # Otherwise, if the gem isn't pinned, the latest version is just the
        # latest commit for the specified branch.
        return latest_resolvable_commit_with_unchanged_git_source unless git_commit_checker.pinned?

        # If the dependency is pinned to a tag that looks like a version then
        # we want to update that tag. The latest version will then be the SHA
        # of the latest tag that looks like a version.
        if git_commit_checker.pinned_ref_looks_like_version? &&
           latest_git_tag_is_resolvable?
          new_tag = git_commit_checker.local_tag_for_latest_version
          return new_tag&.fetch(:tag_sha)
        end

        # If the dependency is pinned to a tag that doesn't look like a
        # version then there's nothing we can do.
        dependency.version
      end

      sig { returns(T.any(String, T.nilable(Dependabot::Bundler::Version))) }
      def latest_resolvable_version_without_git_source
        return nil unless latest_version.is_a?(Gem::Version)

        latest_resolvable_version_details(remove_git_source: true)
          &.fetch(:version)
      rescue Dependabot::DependencyFileNotResolvable
        nil
      end

      sig { returns(T.any(String, T.nilable(Dependabot::Bundler::Version))) }
      def latest_resolvable_commit_with_unchanged_git_source
        details = latest_resolvable_version_details(remove_git_source: false)

        # If this dependency has a git version in the Gemfile.lock but not in
        # the Gemfile (i.e., because they're out-of-sync) we might not get a
        # commit_sha back from Bundler. In that case, return `nil`.
        return unless details&.key?(:commit_sha)

        details.fetch(:commit_sha)
      rescue Dependabot::DependencyFileNotResolvable
        nil
      end

      sig { returns(T::Boolean) }
      def latest_git_tag_is_resolvable?
        latest_tag_details = git_commit_checker.local_tag_for_latest_version
        return false unless latest_tag_details

        git_tag_resolvable?(latest_tag_details.fetch(:tag))
      end

      sig { params(release: T.untyped).returns(T::Boolean) }
      def git_branch_or_ref_in_release?(release)
        return false unless release

        git_commit_checker.branch_or_ref_in_release?(release)
      end

      sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def updated_source
        # Never need to update source, unless a git_dependency
        return dependency_source_details unless git_dependency?

        # Update the git tag if updating a pinned version
        if git_commit_checker.pinned_ref_looks_like_version? &&
           latest_git_tag_is_resolvable?
          new_tag = git_commit_checker.local_tag_for_latest_version
          return T.must(dependency_source_details).merge(ref: T.must(new_tag).fetch(:tag))
        end

        # Otherwise return the original source
        dependency_source_details
      end

      sig { returns(T.nilable(T::Hash[T.any(String, Symbol), T.untyped])) }
      def dependency_source_details
        dependency.source_details
      end

      sig { returns(Dependabot::Bundler::UpdateChecker::ForceUpdater) }
      def force_updater
        if @force_updater.nil?
          @force_updater = T.let(@force_updater,
                                 T.nilable(Dependabot::Bundler::UpdateChecker::ForceUpdater))
        end
        @force_updater ||=
          ForceUpdater.new(
            dependency: dependency,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials,
            target_version: T.cast(latest_version, Dependabot::Version),
            requirements_update_strategy: T.must(requirements_update_strategy),
            options: options
          )
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        if @git_commit_checker.nil?
          @git_commit_checker = T.let(@git_commit_checker,
                                      T.nilable(Dependabot::GitCommitChecker))
        end
        @git_commit_checker ||=
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          )
      end

      sig { params(remove_git_source: T::Boolean, unlock_requirement: T::Boolean).returns(T.untyped) }
      def version_resolver(remove_git_source:, unlock_requirement: true)
        @version_resolver ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
        @version_resolver[remove_git_source] ||= {}
        @version_resolver[remove_git_source][unlock_requirement] ||=
          VersionResolver.new(
            dependency: dependency,
            unprepared_dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            remove_git_source: remove_git_source,
            unlock_requirement: unlock_requirement,
            latest_allowable_version: latest_version,
            cooldown_options: update_cooldown,
            options: options
          )
      end

      sig { params(remove_git_source: T::Boolean).returns(Dependabot::Bundler::UpdateChecker::LatestVersionFinder) }
      def latest_version_finder(remove_git_source:)
        @latest_version_finder ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
        @latest_version_finder[remove_git_source] ||=
          begin
            prepared_dependency_files = prepared_dependency_files(
              remove_git_source: remove_git_source,
              unlock_requirement: true
            )

            LatestVersionFinder.new(
              dependency: dependency,
              dependency_files: prepared_dependency_files,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: raise_on_ignored,
              security_advisories: security_advisories,
              cooldown_options: update_cooldown,
              options: options
            )
          end
      end

      sig do
        params(
          remove_git_source: T::Boolean,
          unlock_requirement: T::Boolean,
          latest_allowable_version: T.nilable(T.any(String, Dependabot::Bundler::Version))
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def prepared_dependency_files(remove_git_source:, unlock_requirement:,
                                    latest_allowable_version: nil)
        FilePreparer.new(
          dependency: dependency,
          dependency_files: dependency_files,
          remove_git_source: remove_git_source,
          unlock_requirement: unlock_requirement,
          latest_allowable_version: latest_allowable_version
        ).prepared_dependency_files
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("bundler", Dependabot::Bundler::UpdateChecker)
