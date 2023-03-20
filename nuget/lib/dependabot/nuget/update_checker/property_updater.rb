# frozen_string_literal: true

require "dependabot/nuget/file_parser"
require "dependabot/nuget/update_checker"

module Dependabot
  module Nuget
    class UpdateChecker
      class PropertyUpdater
        require_relative "version_finder"
        require_relative "requirements_updater"

        def initialize(dependency:, dependency_files:, credentials:,
                       target_version_details:, ignored_versions:,
                       raise_on_ignored: false)
          @dependency       = dependency
          @dependency_files = dependency_files
          @credentials      = credentials
          @ignored_versions = ignored_versions
          @raise_on_ignored = raise_on_ignored
          @target_version   = target_version_details&.fetch(:version)
          @source_details   = target_version_details&.
                              slice(:nuspec_url, :repo_url, :source_url)
        end

        def update_possible?
          return false unless target_version

          @update_possible ||=
            dependencies_using_property.all? do |dep|
              versions = VersionFinder.new(
                dependency: dep,
                dependency_files: dependency_files,
                credentials: credentials,
                ignored_versions: ignored_versions,
                raise_on_ignored: @raise_on_ignored,
                security_advisories: []
              ).versions.map { |v| v.fetch(:version) }

              versions.include?(target_version) || versions.none?
            end
        end

        def updated_dependencies
          raise "Update not possible!" unless update_possible?

          @updated_dependencies ||=
            dependencies_using_property.map do |dep|
              Dependency.new(
                name: dep.name,
                version: target_version.to_s,
                requirements: updated_requirements(dep),
                previous_version: dep.version,
                previous_requirements: dep.requirements,
                package_manager: dep.package_manager
              )
            end
        end

        private

        attr_reader :dependency, :dependency_files, :target_version,
                    :source_details, :credentials, :ignored_versions

        def dependencies_using_property
          @dependencies_using_property ||=
            Nuget::FileParser.new(
              dependency_files: dependency_files,
              source: nil
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

        def updated_requirements(dep)
          @updated_requirements ||= {}
          @updated_requirements[dep.name] ||=
            RequirementsUpdater.new(
              requirements: dep.requirements,
              latest_version: target_version,
              source_details: source_details
            ).updated_requirements
        end
      end
    end
  end
end
