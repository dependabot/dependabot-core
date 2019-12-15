# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Sbt
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/version_finder"
      require_relative "update_checker/requirements_updater"

      def latest_version
        return if git_dependency?

        latest_version_details&.fetch(:version)
      end

      def preferred_version_details
        return lowest_security_fix_version_details if vulnerable?

        latest_version_details
      end

      def latest_version_details
        @latest_version_details ||= version_finder.latest_version_details
      end

      def latest_resolvable_version
        # TODO: Resolve the build.sbt to find the latest version we could
        # update to without updating any other dependencies at the same time.
        #
        # The above is hard. Currently we just return the latest version and
        # hope (hence this package manager is in beta!)
        return if git_dependency?

        latest_version
      end

      def latest_version_resolvable_with_full_unlock?
        false
      end

      def version_finder
        @version_finder ||=
          VersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories
          )
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def git_commit_checker
        @git_commit_checker ||=
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          )
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version&.to_s,
          source_url: preferred_version_details&.fetch(:source_url),
          properties_to_update: []
        ).updated_requirements
      end
    end
  end
end

Dependabot::UpdateCheckers.register("sbt", Dependabot::Sbt::UpdateChecker)
