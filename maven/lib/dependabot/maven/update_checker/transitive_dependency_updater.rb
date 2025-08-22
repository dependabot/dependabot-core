# typed: strict
# frozen_string_literal: true

require "dependabot/package/release_cooldown_options"
require "dependabot/maven/file_parser"
require "dependabot/maven/file_parser/maven_dependency_parser"
require "dependabot/maven/update_checker"
require "sorbet-runtime"

module Dependabot
  module Maven
    class UpdateChecker
      class TransitiveDependencyUpdater
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
            dependencies_depending_on_target.all? do |dep|
              # Check if there's a version of this dependency that's compatible 
              # with the updated target dependency version
              releases = VersionFinder.new(
                dependency: dep,
                dependency_files: dependency_files,
                credentials: credentials,
                ignored_versions: ignored_versions,
                security_advisories: [],
                cooldown_options: update_cooldown
              ).releases

              versions = releases.map(&:version)

              # For now, we'll assume the latest version is compatible
              # In a more sophisticated implementation, we'd parse version constraints
              # and check compatibility
              versions.any?
            end,
            T.nilable(T::Boolean)
          )
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def updated_dependencies
          raise "Update not possible!" unless update_possible?

          @updated_dependencies ||= T.let(
            [updated_target_dependency] + updated_dependent_dependencies,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        # Find dependencies that directly depend on our target dependency
        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies_depending_on_target
          @dependencies_depending_on_target ||= T.let(
            all_dependencies.select do |dep|
              next false if dep.name == dependency.name
              
              # Check if this dependency has our target as a transitive dependency
              depends_on_target?(dep)
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

        # Check if the given dependency depends on our target dependency
        sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
        def depends_on_target?(dep)
          # Use Maven's dependency tree to check if this dependency depends on our target
          # This requires parsing the full dependency tree that includes transitive dependencies
          
          return false unless Dependabot::Experiments.enabled?(:maven_transitive_dependencies)
          
          # Get the complete dependency set which includes transitive dependencies
          dependency_set = Maven::FileParser::MavenDependencyParser.build_dependency_set(dependency_files)
          
          # Find all transitive dependencies for the current dependency
          transitive_deps = dependency_set.dependencies.select do |transitive_dep|
            # Check if this transitive dependency has the same name as our dependency being checked
            # and if its metadata indicates it comes from a pom file that matches our dependency
            transitive_dep.name == dependency.name &&
              transitive_dep.requirements.any? { |req| req.dig(:metadata, :pom_file) }
          end
          
          # If we found our target dependency as a transitive dependency, then this dep depends on it
          transitive_deps.any?
        rescue StandardError => e
          Dependabot.logger.warn("Error checking transitive dependencies: #{e.message}")
          false
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def all_dependencies
          @all_dependencies ||= T.let(
            Maven::FileParser.new(
              dependency_files: dependency_files,
              source: nil
            ).parse,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        sig { returns(Dependabot::Dependency) }
        def updated_target_dependency
          Dependency.new(
            name: dependency.name,
            version: T.must(target_version).to_s,
            requirements: updated_requirements_for_dependency(dependency),
            previous_version: dependency.version,
            previous_requirements: dependency.requirements,
            package_manager: dependency.package_manager
          )
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def updated_dependent_dependencies
          dependencies_depending_on_target.map do |dep|
            # For each dependent dependency, find the latest compatible version
            latest_version = find_latest_compatible_version(dep)
            
            Dependency.new(
              name: dep.name,
              version: latest_version&.to_s || dep.version,
              requirements: updated_requirements_for_dependency(dep, latest_version),
              previous_version: dep.version,
              previous_requirements: dep.requirements,
              package_manager: dep.package_manager
            )
          end
        end

        sig { params(dep: Dependabot::Dependency).returns(T.nilable(Dependabot::Maven::Version)) }
        def find_latest_compatible_version(dep)
          releases = VersionFinder.new(
            dependency: dep,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: [],
            cooldown_options: update_cooldown
          ).releases

          # Return the latest version for now
          # In a more sophisticated implementation, we'd check compatibility
          releases.map(&:version).max
        end

        sig do 
          params(
            dep: Dependabot::Dependency, 
            new_version: T.nilable(Dependabot::Maven::Version)
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def updated_requirements_for_dependency(dep, new_version = nil)
          version_to_use = new_version || target_version
          
          RequirementsUpdater.new(
            requirements: dep.requirements,
            latest_version: version_to_use&.to_s,
            source_url: source_url,
            properties_to_update: []
          ).updated_requirements
        end
      end
    end
  end
end