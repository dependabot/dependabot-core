# frozen_string_literal: true

require "json"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Composer
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"
      require_relative "update_checker/latest_version_finder"

      def latest_version
        return nil if path_dependency?

        # Fall back to latest_resolvable_version if no listings found
        latest_version_from_registry || latest_resolvable_version
      end

      def latest_resolvable_version
        return nil if path_dependency?

        @latest_resolvable_version ||=
          VersionResolver.new(
            credentials: credentials,
            dependency: dependency,
            dependency_files: dependency_files,
            latest_allowable_version: latest_version_from_registry,
            requirements_to_unlock: :own
          ).latest_resolvable_version
      end

      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        if defined?(@lowest_resolvable_security_fix_version)
          return @lowest_resolvable_security_fix_version
        end

        @lowest_resolvable_security_fix_version =
          fetch_lowest_resolvable_security_fix_version
      end

      def latest_resolvable_version_with_no_unlock
        return nil if path_dependency?

        @latest_resolvable_version_with_no_unlock ||=
          VersionResolver.new(
            credentials: credentials,
            dependency: dependency,
            dependency_files: dependency_files,
            latest_allowable_version: latest_version_from_registry,
            requirements_to_unlock: :none
          ).latest_resolvable_version
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_resolvable_version: preferred_resolvable_version&.to_s,
          update_strategy: requirements_update_strategy
        ).updated_requirements
      end

      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        if @requirements_update_strategy
          return @requirements_update_strategy.to_sym
        end

        # Otherwise, widen ranges for libraries and bump versions for apps
        library? ? :widen_ranges : :bump_versions_if_necessary
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Composer (yet)
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def latest_version_from_registry
        latest_version_finder.latest_version
      end

      def latest_version_finder
        @latest_version_finder ||= LatestVersionFinder.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: security_advisories
        )
      end

      def fetch_lowest_resolvable_security_fix_version
        return nil if path_dependency?

        fix_version = latest_version_finder.lowest_security_fix_version
        return latest_resolvable_version if fix_version.nil?

        resolved_fix_version = VersionResolver.new(
          credentials: credentials,
          dependency: dependency,
          dependency_files: dependency_files,
          latest_allowable_version: fix_version,
          requirements_to_unlock: :own
        ).latest_resolvable_version

        return fix_version if fix_version == resolved_fix_version

        latest_resolvable_version
      end

      def path_dependency?
        dependency.requirements.any? { |r| r.dig(:source, :type) == "path" }
      end

      def composer_file
        composer_file =
          dependency_files.find { |f| f.name == "composer.json" }
        raise "No composer.json!" unless composer_file

        composer_file
      end

      def library?
        JSON.parse(composer_file.content)["type"] == "library"
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("composer", Dependabot::Composer::UpdateChecker)
