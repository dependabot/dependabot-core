# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/gradle/file_parser"

module Dependabot
  module Gradle
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_finder"
      require_relative "update_checker/multi_dependency_updater"

      def latest_version
        return if git_dependency?

        latest_version_details&.fetch(:version)
      end

      def latest_resolvable_version
        # TODO: Resolve the build.gradle to find the latest version we could
        # update to without updating any other dependencies at the same time.
        #
        # The above is hard. Currently we just return the latest version and
        # hope (hence this package manager is in beta!)
        return if git_dependency?
        return nil if version_comes_from_multi_dependency_property?
        return nil if version_comes_from_dependency_set?

        latest_version
      end

      def lowest_security_fix_version
        lowest_security_fix_version_details&.fetch(:version)
      end

      def lowest_resolvable_security_fix_version
        return if git_dependency?
        return nil if version_comes_from_multi_dependency_property?
        return nil if version_comes_from_dependency_set?

        lowest_security_fix_version
      end

      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Gradle has a single dependency file.
        #
        # For completeness we ought to resolve the build.gradle and return the
        # latest version that satisfies the current constraint AND any
        # constraints placed on it by other dependencies. Seeing as we're
        # never going to take any action as a result, though, we just return
        # nil.
        nil
      end

      def updated_requirements
        property_names =
          declarations_using_a_property.
          map { |req| req.dig(:metadata, :property_name) }

        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version&.to_s,
          source_url: preferred_version_details&.fetch(:source_url),
          properties_to_update: property_names
        ).updated_requirements
      end

      def requirements_unlocked_or_can_be?
        # If the dependency version come from a property we couldn't
        # interpolate then there's nothing we can do.
        !dependency.version.include?("$")
      end

      private

      def latest_version_resolvable_with_full_unlock?
        unless version_comes_from_multi_dependency_property? ||
               version_comes_from_dependency_set?
          return false
        end

        multi_dependency_updater.update_possible?
      end

      def updated_dependencies_after_full_unlock
        multi_dependency_updater.updated_dependencies
      end

      def numeric_version_up_to_date?
        return false unless version_class.correct?(dependency.version)

        super
      end

      def numeric_version_can_update?(requirements_to_unlock:)
        return false unless version_class.correct?(dependency.version)

        super
      end

      def preferred_version_details
        return lowest_security_fix_version_details if vulnerable?

        latest_version_details
      end

      def latest_version_details
        @latest_version_details ||= version_finder.latest_version_details
      end

      def lowest_security_fix_version_details
        @lowest_security_fix_version_details ||=
          version_finder.lowest_security_fix_version_details
      end

      def version_finder
        @version_finder ||=
          VersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          )
      end

      def multi_dependency_updater
        @multi_dependency_updater ||=
          MultiDependencyUpdater.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            target_version_details: latest_version_details,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored
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

      def version_comes_from_multi_dependency_property?
        declarations_using_a_property.any? do |requirement|
          property_name = requirement.fetch(:metadata).fetch(:property_name)

          all_property_based_dependencies.any? do |dep|
            next false if dep.name == dependency.name

            dep.requirements.any? do |req|
              req.dig(:metadata, :property_name) == property_name
            end
          end
        end
      end

      def version_comes_from_dependency_set?
        dependency.requirements.any? do |req|
          req.dig(:metadata, :dependency_set)
        end
      end

      def declarations_using_a_property
        @declarations_using_a_property ||=
          dependency.requirements.
          select { |req| req.dig(:metadata, :property_name) }
      end

      def all_property_based_dependencies
        @all_property_based_dependencies ||=
          Gradle::FileParser.new(
            dependency_files: dependency_files,
            source: nil
          ).parse.select do |dep|
            dep.requirements.any? { |req| req.dig(:metadata, :property_name) }
          end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("gradle", Dependabot::Gradle::UpdateChecker)
