# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/dependency_requirement"
require "dependabot/maven/distributions"

module Dependabot
  module Maven
    class FileUpdater
      # Splits merged dependency requirements into wrapper-file and POM scopes. DependencySet may
      # combine requirements from multiple wrapper files or from a wrapper and a regular POM entry.
      class DependencyRequirementScopes
        extend T::Sig

        RequirementPair = T.type_alias do
          [Dependabot::DependencyRequirement, T.nilable(Dependabot::DependencyRequirement)]
        end

        sig { params(dependencies: T::Array[Dependabot::Dependency]).void }
        def initialize(dependencies:)
          @dependencies = dependencies
        end

        sig { returns(T::Hash[String, T::Array[Dependabot::Dependency]]) }
        def wrapper_groups
          groups = T.let({}, T::Hash[String, T::Array[Dependabot::Dependency]])
          dependencies.each do |dependency|
            requirement_pairs(dependency)
              .select { |requirement, _| distribution_requirement?(requirement) }
              .group_by { |requirement, _| requirement.file }
              .each do |properties_name, pairs|
                next unless properties_name

                group = groups.fetch(properties_name) { groups[properties_name] = [] }
                group << dependency_with_requirement_pairs(dependency, pairs)
              end
          end
          groups
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(Dependabot::Dependency)) }
        def pom_dependency(dependency)
          pom_pairs = requirement_pairs(dependency).reject do |requirement, _|
            distribution_requirement?(requirement)
          end
          return if pom_pairs.empty?

          dependency_with_requirement_pairs(dependency, pom_pairs)
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { params(dependency: Dependabot::Dependency).returns(T::Array[RequirementPair]) }
        def requirement_pairs(dependency)
          dependency.requirements.zip(dependency.previous_requirements || [])
        end

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T::Boolean) }
        def distribution_requirement?(requirement)
          requirement.source_string("type") == Distributions::DISTRIBUTION_DEPENDENCY_TYPE
        end

        sig do
          params(dependency: Dependabot::Dependency, pairs: T::Array[RequirementPair])
            .returns(Dependabot::Dependency)
        end
        def dependency_with_requirement_pairs(dependency, pairs)
          previous_requirements = dependency.previous_requirements ? pairs.map { |_, previous| T.must(previous) } : nil
          Dependabot::Dependency.new(
            name: dependency.name,
            version: dependency.version,
            requirements: pairs.map { |requirement, _| requirement },
            previous_version: dependency.previous_version,
            previous_requirements: previous_requirements,
            package_manager: dependency.package_manager,
            directory: dependency.directory,
            subdependency_metadata: dependency.subdependency_metadata,
            removed: dependency.removed?,
            metadata: dependency.metadata
          )
        end
      end
    end
  end
end
