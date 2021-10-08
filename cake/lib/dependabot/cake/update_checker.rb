# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/cake/version"
require "dependabot/cake/requirement"

module Dependabot
  module Cake
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/version_finder"
      require "dependabot/nuget/update_checker/requirements_updater"

      def latest_version
        @latest_version = latest_version_details&.fetch(:version)
      end

      def latest_resolvable_version
        latest_version
      end

      def latest_resolvable_version_with_no_unlock
        nil
      end

      def latest_version_resolvable_with_full_unlock?
        false
      end

      def updated_requirements
        Dependabot::Nuget::UpdateChecker::RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version&.to_s,
          source_details: preferred_version_details&.slice(:nuspec_url,
                                                           :repo_url,
                                                           :source_url)
        ).updated_requirements
      end

      private

      def preferred_version_details
        latest_version_details
      end

      def latest_version_details
        @latest_version_details ||= version_finder.latest_version_details
      end

      def version_finder
        @version_finder ||=
          VersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories
          )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("cake", Dependabot::Cake::UpdateChecker)
