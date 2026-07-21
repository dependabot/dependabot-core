# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/gradle/file_parser"
require "dependabot/gradle/update_checker"

module Dependabot
  module Gradle
    class UpdateChecker
      class MultiDependencyUpdater
        extend T::Sig

        require_relative "version_finder"
        require_relative "requirements_updater"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            target_version_details: T.nilable(T::Hash[Symbol, Object]),
            ignored_versions: T::Array[String],
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          target_version_details:,
          ignored_versions:,
          raise_on_ignored: false
        )
          @dependency = T.let(dependency, Dependabot::Dependency)
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
          @target_version = T.let(
            version_from_details(target_version_details),
            T.nilable(Dependabot::Gradle::Version)
          )
          @source_url = T.let(
            source_url_from_details(target_version_details),
            T.nilable(String)
          )
          @ignored_versions = T.let(ignored_versions, T::Array[String])
          @raise_on_ignored = T.let(raise_on_ignored, T::Boolean)
          @update_possible = T.let(nil, T.nilable(T::Boolean))
          @updated_dependencies = T.let(nil, T.nilable(T::Array[Dependabot::Dependency]))
          @dependencies_to_update = T.let(nil, T.nilable(T::Array[Dependabot::Dependency]))
          @property_name = T.let(nil, T.nilable(String))
          @dependency_set = T.let(nil, T.nilable(T::Hash[Symbol, String]))
          @updated_requirements = T.let(
            {},
            T::Hash[String, T::Array[Dependabot::DependencyRequirement]]
          )
        end
        sig { returns(T::Boolean) }
        def update_possible?
          return false unless target_version

          @update_possible ||=
            dependencies_to_update.all? do |dep|
              VersionFinder.new(
                dependency: dep,
                dependency_files: dependency_files,
                credentials: credentials,
                ignored_versions: ignored_versions,
                raise_on_ignored: @raise_on_ignored,
                security_advisories: []
              ).versions
                           .map { |v| v.fetch(:version) }
                           .include?(target_version)
            end
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
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

        sig { params(details: T.nilable(T::Hash[Symbol, Object])).returns(T.nilable(Dependabot::Gradle::Version)) }
        def version_from_details(details)
          version = details&.fetch(:version, nil)
          version if version.is_a?(Dependabot::Gradle::Version)
        end

        sig { params(details: T.nilable(T::Hash[Symbol, Object])).returns(T.nilable(String)) }
        def source_url_from_details(details)
          source_url = details&.fetch(:source_url, nil)
          source_url if source_url.is_a?(String)
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(Dependabot::Gradle::Version)) }
        attr_reader :target_version

        sig { returns(T.nilable(String)) }
        attr_reader :source_url

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies_to_update
          @dependencies_to_update ||=
            Gradle::FileParser.new(
              dependency_files: dependency_files,
              source: nil
            ).parse.select do |dep|
              dep.requirements.any? do |r|
                tmp_p_name = metadata_string(r, :property_name)
                tmp_dep_set = metadata_dependency_set(r)
                next true if property_name && tmp_p_name == property_name

                dependency_set && tmp_dep_set == dependency_set
              end
            end
        end

        sig { returns(T.nilable(String)) }
        def property_name
          @property_name ||= dependency.requirements
                                       .filter_map do |requirement|
                                         metadata_string(requirement, :property_name)
                                       end
                                       .first
        end

        sig { returns(T.nilable(T::Hash[Symbol, String])) }
        def dependency_set
          @dependency_set ||= dependency.requirements
                                        .filter_map do |requirement|
                                          metadata_dependency_set(requirement)
                                        end
                                        .first
        end

        sig do
          params(
            dep: Dependabot::Dependency
          ).returns(T::Array[Dependabot::DependencyRequirement])
        end
        def updated_requirements(dep)
          @updated_requirements[dep.name] ||=
            RequirementsUpdater.new(
              requirements: dep.requirements,
              latest_version: target_version.to_s,
              source_url: source_url,
              properties_to_update: [property_name].compact
            ).updated_requirements
        end

        sig do
          params(
            requirement: Dependabot::DependencyRequirement,
            key: Symbol
          ).returns(T.nilable(String))
        end
        def metadata_string(requirement, key)
          value = requirement.metadata&.[](key)
          value if value.is_a?(String)
        end

        sig do
          params(
            requirement: Dependabot::DependencyRequirement
          ).returns(T.nilable(T::Hash[Symbol, String]))
        end
        def metadata_dependency_set(requirement)
          value = requirement.metadata&.[](:dependency_set)
          return unless value.is_a?(Hash)

          details = T.let(value, T::Hash[Object, Object])
          details.each_with_object(T.let({}, T::Hash[Symbol, String])) do |(key, entry), result|
            valid_entry = key.is_a?(Symbol) && entry.is_a?(String)
            raise TypeError, "dependency_set metadata must use symbol keys and string values" unless valid_entry

            result[key] = entry
          end
        end
      end
    end
  end
end
