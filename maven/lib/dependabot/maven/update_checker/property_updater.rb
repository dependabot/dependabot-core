# typed: strict
# frozen_string_literal: true

require "dependabot/package/release_cooldown_options"
require "dependabot/maven/file_parser"
require "dependabot/maven/update_checker"
require "dependabot/maven/file_updater/declaration_finder"
require "sorbet-runtime"

module Dependabot
  module Maven
    class UpdateChecker
      class PropertyUpdater
        extend T::Sig

        require_relative "requirements_updater"
        require_relative "version_finder"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            target_version_details: T.nilable(T::Hash[T.untyped, T.untyped]),
            update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:, dependency_files:, credentials:,
          ignored_versions:, target_version_details:,
          update_cooldown: nil
        )
          @dependency       = dependency
          @dependency_files = dependency_files
          @credentials      = credentials
          @ignored_versions = ignored_versions
          @target_version   = T.let(target_version_details&.fetch(:version), T.nilable(Dependabot::Maven::Version))
          @source_url       = T.let(target_version_details&.fetch(:source_url), T.nilable(String))
          @update_cooldown = update_cooldown
        end

        sig { returns(T::Boolean) }
        def update_possible?
          return false unless target_version
          return T.must(@update_possible) if defined?(@update_possible)

          @update_possible ||= T.let(
            dependencies_using_property.all? do |dep|
              next false if includes_property_reference?(updated_version(dep))

              releases = VersionFinder.new(
                dependency: dep,
                dependency_files: dependency_files,
                credentials: credentials,
                ignored_versions: ignored_versions,
                security_advisories: [],
                cooldown_options: update_cooldown
              ).releases

              versions = releases.map(&:version)

              versions.include?(updated_version(dep)) || versions.none?
            end,
            T.nilable(T::Boolean)
          )
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def updated_dependencies
          raise "Update not possible!" unless update_possible?

          @updated_dependencies ||= T.let(
            dependencies_using_property.map do |dep|
              Dependency.new(
                name: dep.name,
                version: updated_version(dep),
                requirements: updated_requirements(dep),
                previous_version: dep.version,
                previous_requirements: dep.requirements,
                package_manager: dep.package_manager,
                origin_files: dep.origin_files
              )
            end,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(Dependabot::Maven::Version)) }
        attr_reader :target_version

        sig { returns(T.nilable(String)) }
        attr_reader :source_url

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :update_cooldown

        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies_using_property
          @dependencies_using_property ||= T.let(
            Maven::FileParser.new(
              dependency_files: dependency_files,
              source: nil
            ).parse.select do |dep|
              dep.requirements.any? do |r|
                next unless r.dig(:metadata, :property_name) == property_name

                r.dig(:metadata, :property_source) == property_source
              end
            end,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        sig { returns(String) }
        def property_name
          @property_name ||= T.let(
            dependency.requirements
                      .find { |r| r.dig(:metadata, :property_name) }
                      &.dig(:metadata, :property_name),
            T.nilable(String)
          )

          raise "No requirement with a property name!" unless @property_name

          @property_name
        end

        sig { returns(T.nilable(String)) }
        def property_source
          @property_source ||= T.let(
            dependency.requirements
                      .find { |r| r.dig(:metadata, :property_name) == property_name }
                      &.dig(:metadata, :property_source),
            T.nilable(String)
          )
        end

        sig { params(string: String).returns(T::Boolean) }
        def includes_property_reference?(string)
          string.match?(Maven::FileParser::PROPERTY_REGEX)
        end

        sig { params(dep: Dependabot::Dependency).returns(T.nilable(String)) }
        def version_string(dep)
          declaring_requirement =
            dep.requirements
               .find { |r| r.dig(:metadata, :property_name) == property_name }

          Maven::FileUpdater::DeclarationFinder.new(
            dependency: dep,
            declaring_requirement: T.must(declaring_requirement),
            dependency_files: dependency_files
          ).declaration_nodes.first&.at_css("version")&.content
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pom
          dependency_files.find { |f| f.name == "pom.xml" }
        end

        sig { params(dep: Dependabot::Dependency).returns(String) }
        def updated_version(dep)
          T.must(version_string(dep)).gsub("${#{property_name}}", T.must(target_version).to_s)
        end

        sig { params(dep: Dependabot::Dependency).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements(dep)
          @updated_requirements ||= T.let({}, T.nilable(T::Hash[String, T::Array[T::Hash[Symbol, T.untyped]]]))
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
