# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers/base"
require "dependabot/nuget/file_parser"

module Dependabot
  module Nuget
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class PropertyUpdater
        extend T::Sig

        require_relative "version_finder"
        require_relative "requirements_updater"
        require_relative "dependency_finder"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            target_version_details: T.nilable(T::Hash[Symbol, String]),
            ignored_versions: T::Array[String],
            repo_contents_path: T.nilable(String),
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:,
                       target_version_details:, ignored_versions:,
                       repo_contents_path:, raise_on_ignored: false)
          @dependency       = dependency
          @dependency_files = dependency_files
          @credentials      = credentials
          @ignored_versions = ignored_versions
          @raise_on_ignored = raise_on_ignored
          @target_version   = T.let(
            target_version_details&.fetch(:version),
            T.nilable(T.any(String, Dependabot::Nuget::Version))
          )
          @source_details = T.let(
            target_version_details&.slice(:nuspec_url, :repo_url, :source_url),
            T.nilable(T::Hash[Symbol, String])
          )
          @repo_contents_path = repo_contents_path
        end

        sig { returns(T::Boolean) }
        def update_possible?
          return false unless target_version

          @update_possible ||= T.let(
            dependencies_using_property.all? do |dep|
              versions = VersionFinder.new(
                dependency: dep,
                dependency_files: dependency_files,
                credentials: credentials,
                ignored_versions: ignored_versions,
                raise_on_ignored: @raise_on_ignored,
                security_advisories: [],
                repo_contents_path: repo_contents_path
              ).versions.map { |v| v.fetch(:version) }

              versions.include?(target_version) || versions.none?
            end,
            T.nilable(T::Boolean)
          )
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def updated_dependencies
          raise "Update not possible!" unless update_possible?

          @updated_dependencies ||= T.let(
            begin
              dependencies = T.let({}, T::Hash[String, Dependabot::Dependency])

              dependencies_using_property.each do |dep|
                # Only keep one copy of each dependency, the one with the highest target version.
                visited_dependency = dependencies[dep.name.downcase]
                next unless visited_dependency.nil? || T.must(visited_dependency.numeric_version) < target_version

                updated_dependency = Dependency.new(
                  name: dep.name,
                  version: target_version.to_s,
                  requirements: updated_requirements(dep),
                  previous_version: dep.version,
                  previous_requirements: dep.requirements,
                  package_manager: dep.package_manager
                )
                dependencies[updated_dependency.name.downcase] = updated_dependency
                # Add peer dependencies to the list of updated dependencies.
                process_updated_peer_dependencies(updated_dependency, dependencies)
              end

              dependencies.map { |_, dependency| dependency }
            end,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(T.any(String, Dependabot::Nuget::Version))) }
        attr_reader :target_version

        sig { returns(T.nilable(T::Hash[Symbol, String])) }
        attr_reader :source_details

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependencies: T::Hash[String, Dependabot::Dependency]
          )
            .returns(T::Array[Dependabot::Dependency])
        end
        def process_updated_peer_dependencies(dependency, dependencies)
          DependencyFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path
          ).updated_peer_dependencies.each do |peer_dependency|
            # Only keep one copy of each dependency, the one with the highest target version.
            visited_dependency = dependencies[peer_dependency.name.downcase]
            unless visited_dependency.nil? ||
                   T.must(visited_dependency.numeric_version) < peer_dependency.numeric_version
              next
            end

            dependencies[peer_dependency.name.downcase] = peer_dependency
          end
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies_using_property
          @dependencies_using_property ||=
            T.let(
              Nuget::FileParser.new(
                dependency_files: dependency_files,
                source: nil
              ).parse.select do |dep|
                dep.requirements.any? do |r|
                  r.dig(:metadata, :property_name) == property_name
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

        sig { params(dep: Dependabot::Dependency).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements(dep)
          @updated_requirements ||= T.let({}, T.nilable(T::Hash[String, T::Array[T::Hash[Symbol, T.untyped]]]))
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
