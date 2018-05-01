# frozen_string_literal: true

require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Java
      class Gradle < Dependabot::UpdateCheckers::Base
        require_relative "maven/requirements_updater"
        require_relative "gradle/version_finder"

        def latest_version
          latest_version_details&.fetch(:version)
        end

        def latest_resolvable_version
          # TODO: Resolve the build.gradle to find the latest version we could
          # update to without updating any other dependencies at the same time.
          #
          # The above is hard. Currently we just return the latest version and
          # hope (hence this package manager is in beta!)
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          # Irrelevant, since Gradle has a single dependency file (the pom.xml).
          #
          # For completeness we ought to resolve the build.gradle and return the
          # latest version that satisfies the current constraint AND any
          # constraints placed on it by other dependencies. Seeing as we're
          # never going to take any action as a result, though, we just return
          # nil.
          nil
        end

        def updated_requirements
          Maven::RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            source_url: latest_version_details&.fetch(:source_url)
          ).updated_requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't relevant for Gradle until we start
          # updating property versions
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
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
      end
    end
  end
end
