# frozen_string_literal: true

require "dependabot/git_commit_checker"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "set"

module Dependabot
  module NpmAndYarn
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/library_detector"
      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/version_resolver"
      require_relative "update_checker/subdependency_version_resolver"
      require_relative "update_checker/conflicting_dependency_resolver"
      require_relative "update_checker/vulnerability_auditor"

      def up_to_date?
        return false if security_update? &&
                        dependency.version &&
                        version_class.correct?(dependency.version) &&
                        vulnerable_versions.any? &&
                        !vulnerable_versions.include?(current_version)

        super
      end

      def vulnerable?
        super || vulnerable_versions.any?
      end

      def latest_version
        @latest_version ||=
          if git_dependency?
            latest_version_for_git_dependency
          else
            latest_version_details&.fetch(:version)
          end
      end

      def latest_resolvable_version
        return unless latest_version

        @latest_resolvable_version ||=
          if dependency.top_level?
            version_resolver.latest_resolvable_version
          else
            # If the dependency is indirect its version is constrained  by the
            # requirements placed on it by dependencies lower down the tree
            subdependency_version_resolver.latest_resolvable_version
          end
      end

      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
      end

      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?
        # NOTE: we currently don't resolve transitive/sub-dependencies as
        # npm/yarn don't provide any control over updating to a specific
        # sub-dependency version
        return latest_resolvable_transitive_security_fix_version_with_no_unlock unless dependency.top_level?

        # TODO: Might want to check resolvability here?
        lowest_security_fix_version
      end

      def latest_resolvable_version_with_no_unlock
        return latest_resolvable_version unless dependency.top_level?

        return latest_resolvable_version_with_no_unlock_for_git_dependency if git_dependency?

        latest_version_finder.latest_version_with_no_unlock
      end

      def latest_resolvable_previous_version(updated_version)
        version_resolver.latest_resolvable_previous_version(updated_version)
      end

      def updated_requirements
        resolvable_version =
          if preferred_resolvable_version.is_a?(version_class)
            preferred_resolvable_version.to_s
          elsif preferred_resolvable_version.nil?
            nil
          else
            # If the preferred_resolvable_version came back as anything other
            # than a version class or `nil` it must be because this is a git
            # dependency, for which we don't check resolvability.
            latest_version_details&.fetch(:version, nil)&.to_s
          end

        @updated_requirements ||=
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            updated_source: updated_source,
            latest_resolvable_version: resolvable_version,
            update_strategy: requirements_update_strategy
          ).updated_requirements
      end

      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        return @requirements_update_strategy.to_sym if @requirements_update_strategy

        # Otherwise, widen ranges for libraries and bump versions for apps
        library? ? :widen_ranges : :bump_versions
      end

      def conflicting_dependencies
        conflicts = ConflictingDependencyResolver.new(
          dependency_files: dependency_files,
          credentials: credentials
        ).conflicting_dependencies(
          dependency: dependency,
          target_version: lowest_security_fix_version
        )
        return conflicts unless vulnerability_audit_performed?

        vulnerable = [vulnerability_audit].select do |hash|
          !hash["fix_available"] && hash["explanation"]
        end

        conflicts + vulnerable
      end

      private

      def vulnerability_audit_performed?
        defined?(@vulnerability_audit)
      end

      def vulnerability_audit
        @vulnerability_audit ||=
          VulnerabilityAuditor.new(
            dependency_files: dependency_files,
            credentials: credentials,
            allow_removal: @options.key?(:npm_transitive_dependency_removal)
          ).audit(
            dependency: dependency,
            security_advisories: security_advisories
          )
      end

      def vulnerable_versions
        @vulnerable_versions ||=
          begin
            all_versions = dependency.all_versions.
                           filter_map { |v| version_class.new(v) if version_class.correct?(v) }

            all_versions.select do |v|
              security_advisories.any? { |advisory| advisory.vulnerable?(v) }
            end
          end
      end

      def latest_version_resolvable_with_full_unlock?
        return false unless latest_version

        return version_resolver.latest_version_resolvable_with_full_unlock? if dependency.top_level?

        return false unless security_advisories.any?

        vulnerability_audit["fix_available"]
      end

      def updated_dependencies_after_full_unlock
        return conflicting_updated_dependencies if !dependency.top_level? && security_advisories.any?

        version_resolver.dependency_updates_from_full_unlock.
          map { |update_details| build_updated_dependency(update_details) }
      end

      # rubocop:disable Metrics/AbcSize
      def conflicting_updated_dependencies
        top_level_dependencies = top_level_dependency_lookup

        updated_deps = []
        vulnerability_audit["fix_updates"].each do |update|
          dependency_name = update["dependency_name"]
          requirements = top_level_dependencies[dependency_name]&.requirements || []

          updated_deps << build_updated_dependency(
            dependency: Dependency.new(
              name: dependency_name,
              package_manager: "npm_and_yarn",
              requirements: requirements
            ),
            version: update["target_version"],
            previous_version: update["current_version"]
          )
        end
        # rubocop:enable Metrics/AbcSize

        # We don't need to directly update the target dependency if it will
        # be updated as a side effect of updating the parent. However, we need
        # to include it so it's described in the PR and we'll pass validation
        # that this dependency is at a non-vulnerable version.
        if updated_deps.none? { |dep| dep.name == dependency.name }
          target_version = vulnerability_audit["target_version"]
          updated_deps << build_updated_dependency(
            dependency: dependency,
            version: target_version,
            previous_version: dependency.version,
            removed: target_version.nil?,
            metadata: { information_only: true } # Instruct updater to not directly update this dependency
          )
        end

        # Target dependency should be first in the result to support rebases
        updated_deps.select { |dep| dep.name == dependency.name } +
          updated_deps.reject { |dep| dep.name == dependency.name }
      end

      def top_level_dependency_lookup
        top_level_dependencies = FileParser.new(
          dependency_files: dependency_files,
          credentials: credentials,
          source: nil
        ).parse.select(&:top_level?)

        top_level_dependencies.to_h { |dep| [dep.name, dep] }
      end

      def build_updated_dependency(update_details)
        original_dep = update_details.fetch(:dependency)
        removed = update_details.fetch(:removed, false)
        version = update_details.fetch(:version).to_s unless removed
        previous_version = update_details.fetch(:previous_version)&.to_s
        metadata = update_details.fetch(:metadata, {})

        Dependency.new(
          name: original_dep.name,
          version: version,
          requirements: RequirementsUpdater.new(
            requirements: original_dep.requirements,
            updated_source: original_dep == dependency ? updated_source : original_source(original_dep),
            latest_resolvable_version: version,
            update_strategy: requirements_update_strategy
          ).updated_requirements,
          previous_version: previous_version,
          previous_requirements: original_dep.requirements,
          package_manager: original_dep.package_manager,
          removed: removed,
          metadata: metadata
        )
      end

      def latest_resolvable_transitive_security_fix_version_with_no_unlock
        fix_possible = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
          [latest_resolvable_version].compact,
          security_advisories
        ).any?
        return nil unless fix_possible

        latest_resolvable_version
      end

      def latest_resolvable_version_with_no_unlock_for_git_dependency
        reqs = dependency.requirements.filter_map do |r|
          next if r.fetch(:requirement).nil?

          requirement_class.requirements_array(r.fetch(:requirement))
        end

        current_version =
          if existing_version_is_sha? ||
             !version_class.correct?(dependency.version)
            dependency.version
          else
            version_class.new(dependency.version)
          end

        return current_version if git_commit_checker.pinned?

        # TODO: Really we should get a tag that satisfies the semver req
        return current_version if reqs.any?

        git_commit_checker.head_commit_for_current_branch
      end

      def latest_version_for_git_dependency
        @latest_version_for_git_dependency ||=
          if version_class.correct?(dependency.version)
            latest_git_version_details[:version] &&
              version_class.new(latest_git_version_details[:version])
          else
            latest_git_version_details[:sha]
          end
      end

      def latest_released_version
        @latest_released_version ||=
          latest_version_finder.latest_version_from_registry
      end

      def latest_version_details
        @latest_version_details ||=
          if git_dependency?
            latest_git_version_details
          else
            { version: latest_released_version }
          end
      end

      def latest_version_finder
        @latest_version_finder ||=
          LatestVersionFinder.new(
            dependency: dependency,
            credentials: credentials,
            dependency_files: dependency_files,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          )
      end

      def version_resolver
        @version_resolver ||=
          VersionResolver.new(
            dependency: dependency,
            credentials: credentials,
            dependency_files: dependency_files,
            latest_allowable_version: latest_version,
            latest_version_finder: latest_version_finder,
            repo_contents_path: repo_contents_path
          )
      end

      def subdependency_version_resolver
        @subdependency_version_resolver ||=
          SubdependencyVersionResolver.new(
            dependency: dependency,
            credentials: credentials,
            dependency_files: dependency_files,
            ignored_versions: ignored_versions,
            latest_allowable_version: latest_version,
            repo_contents_path: repo_contents_path
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
        return { sha: git_commit_checker.head_commit_for_current_branch } unless git_commit_checker.pinned?

        # If the dependency is pinned to a tag that doesn't look like a
        # version then there's nothing we can do.
        { sha: dependency.version }
      end

      def updated_source
        # Never need to update source, unless a git_dependency
        return dependency_source_details unless git_dependency?

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
          LibraryDetector.new(
            package_json_file: package_json,
            credentials: credentials,
            dependency_files: dependency_files
          ).library?
      end

      def security_update?
        security_advisories.any?
      end

      def dependency_source_details
        original_source(dependency)
      end

      def original_source(updated_dependency)
        sources =
          updated_dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact.
          sort_by { |source| RegistryFinder.central_registry?(source[:url]) ? 1 : 0 }

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
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored
          )
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("npm_and_yarn", Dependabot::NpmAndYarn::UpdateChecker)
