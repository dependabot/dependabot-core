# frozen_string_literal: true

require "dependabot/gradle/file_parser"
require "dependabot/gradle/update_checker"

module Dependabot
  module Gradle
    class UpdateChecker
      class MultiDependencyUpdater
        require_relative "version_finder"
        require_relative "requirements_updater"

        def initialize(dependency:, dependency_files:,
                       target_version_details:, ignored_versions:)
          @dependency       = dependency
          @dependency_files = dependency_files
          @target_version   = target_version_details&.fetch(:version)
          @source_url       = target_version_details&.fetch(:source_url)
          @ignored_versions = ignored_versions
        end

        def update_possible?
          return false unless target_version

          @update_possible ||=
            dependencies_to_update.all? do |dep|
              VersionFinder.new(
                dependency: dep,
                dependency_files: dependency_files,
                ignored_versions: ignored_versions
              ).versions.
                map { |v| v.fetch(:version) }.
                include?(target_version)
            end
        end

        def updated_dependencies
          raise "Update not possible!" unless update_possible?

          @updated_dependencies ||=
            dependencies_to_update.map do |dep|
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
                    :source_url, :ignored_versions

        def dependencies_to_update
          @dependencies_to_update ||=
            Gradle::FileParser.new(
              dependency_files: dependency_files,
              source: nil
            ).parse.select do |dep|
              dep.requirements.any? do |r|
                tmp_p_name = r.dig(:metadata, :property_name)
                tmp_dep_set = r.dig(:metadata, :dependency_set)
                next true if property_name && tmp_p_name == property_name

                dependency_set && tmp_dep_set == dependency_set
              end
            end
        end

        def property_name
          @property_name ||= dependency.requirements.
                             find { |r| r.dig(:metadata, :property_name) }&.
                             dig(:metadata, :property_name)
        end

        def dependency_set
          @dependency_set ||= dependency.requirements.
                              find { |r| r.dig(:metadata, :dependency_set) }&.
                              dig(:metadata, :dependency_set)
        end

        def pom
          dependency_files.find { |f| f.name == "pom.xml" }
        end

        def updated_requirements(dep)
          @updated_requirements ||= {}
          @updated_requirements[dep.name] ||=
            RequirementsUpdater.new(
              requirements: dep.requirements,
              latest_version: target_version.to_s,
              source_url: source_url,
              properties_to_update: [property_name].compact
            ).updated_requirements
        end
      end
    end
  end
end
