# frozen_string_literal: true

require "dependabot/nuget/file_parser"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Nuget
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/version_finder"
      require_relative "update_checker/property_updater"
      require_relative "update_checker/requirements_updater"

      def latest_version
        @latest_version = latest_version_details&.fetch(:version)
      end

      def latest_resolvable_version
        # TODO: Check version resolution!
        return nil if version_comes_from_multi_dependency_property?

        latest_version
      end

      def lowest_resolvable_security_fix_version
        return nil if version_comes_from_multi_dependency_property?

        lowest_security_fix_version_details&.fetch(:version)
      end

      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Nuget has a single dependency file
        nil
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version&.to_s,
          source_details: preferred_version_details&.
                          slice(:nuspec_url, :repo_url, :source_url)
        ).updated_requirements
      end

      def up_to_date?
        # If any requirements have an uninterpolated property in them then
        # that property couldn't be found, and we assume that the dependency
        # is up-to-date
        return true unless requirements_unlocked_or_can_be?

        super
      end

      def requirements_unlocked_or_can_be?
        # If any requirements have an uninterpolated property in them then
        # that property couldn't be found, and the requirement therefore
        # cannot be unlocked (since we can't update that property)
        namespace = Nuget::FileParser::PropertyValueFinder
        dependency.requirements.none? do |req|
          req.fetch(:requirement)&.match?(namespace::PROPERTY_REGEX)
        end
      end

      private

      def latest_version_resolvable_with_full_unlock?
        return false unless version_comes_from_multi_dependency_property?

        property_updater.update_possible?
      end

      def updated_dependencies_after_full_unlock
        property_updater.updated_dependencies
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
            security_advisories: security_advisories
          )
      end

      def property_updater
        @property_updater ||=
          PropertyUpdater.new(
            dependency: dependency,
            dependency_files: dependency_files,
            target_version_details: latest_version_details,
            credentials: credentials,
            ignored_versions: ignored_versions
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

      def declarations_using_a_property
        @declarations_using_a_property ||=
          dependency.requirements.
          select { |req| req.dig(:metadata, :property_name) }
      end

      def all_property_based_dependencies
        @all_property_based_dependencies ||=
          Nuget::FileParser.new(
            dependency_files: dependency_files,
            source: nil
          ).parse.select do |dep|
            dep.requirements.any? { |req| req.dig(:metadata, :property_name) }
          end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("nuget", Dependabot::Nuget::UpdateChecker)
