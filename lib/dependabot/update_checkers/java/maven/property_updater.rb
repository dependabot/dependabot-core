# frozen_string_literal: true

require "dependabot/file_parsers/java/maven"
require "dependabot/update_checkers/java/maven"
require "dependabot/update_checkers/java/maven/requirements_updater"
require "dependabot/file_updaters/java/maven/declaration_finder"

module Dependabot
  module UpdateCheckers
    module Java
      class Maven
        class PropertyUpdater
          def initialize(dependency:, dependency_files:,
                         target_version_details:)
            @dependency       = dependency
            @dependency_files = dependency_files
            @target_version   = target_version_details&.fetch(:version)
            @source_url       = target_version_details&.fetch(:source_url)
          end

          def update_possible?
            return false unless target_version
            @update_possible ||=
              dependencies_using_property.all? do |dep|
                VersionFinder.new(
                  dependency: dep,
                  dependency_files: dependency_files
                ).versions.
                  map { |v| v.fetch(:version) }.
                  include?(target_version)
              end
          end

          def updated_dependencies
            raise "Update not possible!" unless update_possible?

            @updated_dependencies ||=
              dependencies_using_property.map do |dep|
                Dependency.new(
                  name: dep.name,
                  version: updated_version(dep),
                  requirements: updated_requirements(dep),
                  previous_version: dep.version,
                  previous_requirements: dep.requirements,
                  package_manager: dep.package_manager
                )
              end
          end

          private

          attr_reader :dependency, :dependency_files, :target_version,
                      :source_url

          def dependencies_using_property
            @dependencies_using_property ||=
              FileParsers::Java::Maven.new(
                dependency_files: dependency_files,
                repo: nil
              ).parse.select do |dep|
                dep.requirements.any? do |r|
                  r.dig(:metadata, :property_name) == property_name
                end
              end
          end

          def property_name
            @property_name ||= dependency.requirements.
                               find { |r| r.dig(:metadata, :property_name) }&.
                               dig(:metadata, :property_name)

            raise "No requirement with a property name!" unless @property_name
            @property_name
          end

          def version_string(dep)
            FileUpdaters::Java::Maven::DeclarationFinder.new(
              dependency: dep,
              declaring_requirement: dep.requirements.first,
              dependency_files: dependency_files
            ).declaration_node.at_css("version")&.content
          end

          def pom
            dependency_files.find { |f| f.name == "pom.xml" }
          end

          def updated_version(dep)
            version_string(dep).gsub("${#{property_name}}", target_version.to_s)
          end

          def updated_requirements(dep)
            @updated_requirements ||= {}
            @updated_requirements[dep.name] ||=
              RequirementsUpdater.new(
                requirements: dep.requirements,
                latest_version: updated_version(dep),
                source_url: source_url
              ).updated_requirements
          end
        end
      end
    end
  end
end
