# frozen_string_literal: true

require "dependabot/maven/file_parser"
require "dependabot/maven/update_checker"
require "dependabot/maven/file_updater/declaration_finder"

module Dependabot
  module Maven
    class UpdateChecker
      class PropertyUpdater
        require_relative "requirements_updater"
        require_relative "version_finder"

        def initialize(dependency:, dependency_files:, credentials:,
                       target_version_details:, ignored_versions:)
          @dependency       = dependency
          @dependency_files = dependency_files
          @credentials      = credentials
          @ignored_versions = ignored_versions
          @target_version   = target_version_details&.fetch(:version)
          @source_url       = target_version_details&.fetch(:source_url)
        end

        def update_possible?
          return false unless target_version
          return @update_possible if defined?(@update_possible)

          @update_possible =
            dependencies_using_property.all? do |dep|
              next false if includes_property_reference?(updated_version(dep))

              versions = VersionFinder.new(
                dependency: dep,
                dependency_files: dependency_files,
                credentials: credentials,
                ignored_versions: ignored_versions,
                security_advisories: []
              ).versions.map { |v| v.fetch(:version) }

              versions.include?(updated_version(dep)) || versions.none?
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
                    :source_url, :credentials, :ignored_versions

        def dependencies_using_property
          @dependencies_using_property ||=
            Maven::FileParser.new(
              dependency_files: dependency_files,
              source: nil
            ).parse.select do |dep|
              dep.requirements.any? do |r|
                next unless r.dig(:metadata, :property_name) == property_name

                r.dig(:metadata, :property_source) == property_source
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

        def property_source
          @property_source ||=
            dependency.requirements.
            find { |r| r.dig(:metadata, :property_name) == property_name }&.
            dig(:metadata, :property_source)
        end

        def includes_property_reference?(string)
          string.match?(Maven::FileParser::PROPERTY_REGEX)
        end

        def version_string(dep)
          declaring_requirement =
            dep.requirements.
            find { |r| r.dig(:metadata, :property_name) == property_name }

          Maven::FileUpdater::DeclarationFinder.new(
            dependency: dep,
            declaring_requirement: declaring_requirement,
            dependency_files: dependency_files
          ).declaration_nodes.first.at_css("version")&.content
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
              source_url: source_url,
              properties_to_update: [property_name]
            ).updated_requirements
        end
      end
    end
  end
end
