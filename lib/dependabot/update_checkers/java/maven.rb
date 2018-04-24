# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/file_parsers/java/maven/property_value_finder"

module Dependabot
  module UpdateCheckers
    module Java
      class Maven < Dependabot::UpdateCheckers::Base
        require_relative "maven/requirements_updater"
        require_relative "maven/version_finder"
        require_relative "maven/property_updater"

        def latest_version
          latest_version_details&.fetch(:version)
        end

        def latest_resolvable_version
          # TODO: Resolve the pom.xml to find the latest version we could update
          # to without updating any other dependencies at the same time
          #
          # The above is hard. Currently we just return the latest version and
          # hope (hence this package manager is in beta!)
          return nil if version_comes_from_multi_dependency_property?
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          # Irrelevant, since Maven has a single dependency file (the pom.xml).
          #
          # For completeness we ought to resolve the pom.xml and return the
          # latest version that satisfies the current constraint AND any
          # constraints placed on it by other dependencies. Seeing as we're
          # never going to take any action as a result, though, we just return
          # nil.
          nil
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            source_url: latest_version_details&.fetch(:source_url)
          ).updated_requirements
        end

        def requirements_unlocked_or_can_be?
          declarations_using_a_property.none? do |requirement|
            prop_name = requirement.dig(:metadata, :property_name)
            pom = dependency_files.find { |f| f.name == requirement[:file] }

            declaration_pom_name =
              property_value_finder.
              property_details(property_name: prop_name, callsite_pom: pom)&.
              fetch(:file)

            declaration_pom_name == "remote_pom.xml" ||
              declaration_pom_name.end_with?("pom_parent.xml")
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

        def numeric_version_up_to_date?
          return false unless version_class.correct?(dependency.version)
          super
        end

        def numeric_version_can_update?(requirements_to_unlock:)
          return false unless version_class.correct?(dependency.version)
          super
        end

        def latest_version_details
          @latest_version_details ||= version_finder.latest_version_details
        end

        def version_finder
          @version_finder ||=
            VersionFinder.new(
              dependency: dependency,
              dependency_files: dependency_files
            )
        end

        def property_updater
          @property_updater ||=
            PropertyUpdater.new(
              dependency: dependency,
              dependency_files: dependency_files,
              target_version_details: latest_version_details
            )
        end

        def property_value_finder
          @property_value_finder ||=
            FileParsers::Java::Maven::PropertyValueFinder.
            new(dependency_files: dependency_files)
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
            FileParsers::Java::Maven.new(
              dependency_files: dependency_files,
              repo: nil
            ).parse.select do |dep|
              dep.requirements.any? { |req| req.dig(:metadata, :property_name) }
            end
        end
      end
    end
  end
end
