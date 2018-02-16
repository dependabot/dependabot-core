# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/file_updaters/java/maven/declaration_finder"

module Dependabot
  module UpdateCheckers
    module Java
      class Maven < Dependabot::UpdateCheckers::Base
        require_relative "maven/requirements_updater"
        require_relative "maven/version"
        require_relative "maven/version_finder"
        require_relative "maven/property_updater"

        def latest_version
          VersionFinder.new(dependency: dependency).latest_release
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
            latest_version: latest_version&.to_s
          ).updated_requirements
        end

        def version_class
          Maven::Version
        end

        private

        def latest_version_resolvable_with_full_unlock?
          return false unless version_comes_from_multi_dependency_property?
          property_updater.update_possible?
        end

        def updated_dependencies_after_full_unlock
          property_updater.updated_dependencies
        end

        def property_updater
          @property_updater ||=
            PropertyUpdater.new(
              dependency: dependency,
              dependency_files: dependency_files,
              target_version: latest_version
            )
        end

        def version_comes_from_multi_dependency_property?
          return false unless version_comes_from_property?
          multiple_dependencies_use_property?(original_pom_version_content)
        end

        def version_comes_from_property?
          original_pom_version_content.start_with?("${")
        end

        def multiple_dependencies_use_property?(property)
          property_regex = /#{Regexp.escape(property)}/
          pom.content.scan(property_regex).count > 1
        end

        def original_pom_version_content
          @declaration_node ||=
            FileUpdaters::Java::Maven::DeclarationFinder.new(
              dependency_name: dependency.name,
              pom_content: pom.content
            ).declaration_node

          @declaration_node.at_css("version").content
        end

        def pom
          @pom ||= dependency_files.find { |f| f.name == "pom.xml" }
        end
      end
    end
  end
end
