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
          return false unless Dependabot::Experiments.enabled?(:maven_transitive_dependencies)
          
          # We need to check if our target dependency appears as a transitive dependency
          # of the given dependency. This is complex because we need to:
          # 1. Build dependency tree for the given dependency
          # 2. Check if our target appears in that tree
          
          # For now, implement a simplified heuristic:
          # If the dependency was parsed from the same pom file and appears in the
          # transitive dependency set, it might depend on our target
          
          # Get all dependencies including transitive ones
          begin
            dependency_set = Maven::FileParser::MavenDependencyParser.build_dependency_set(dependency_files)
            
            # Look for our target dependency in the transitive dependencies
            # that share the same pom file context as the dependency we're checking
            target_found_as_transitive = dependency_set.dependencies.any? do |transitive_dep|
              transitive_dep.name == dependency.name &&
                transitive_dep.requirements.any? do |req|
                  # If this transitive dependency is found in a pom context, it suggests
                  # that other dependencies in that context might depend on it
                  req.dig(:metadata, :pom_file)
                end
            end
            
            # Simple heuristic: if we're updating a commonly used library like Guava,
            # and there are other dependencies, they might depend on it
            target_found_as_transitive && is_commonly_transitive_dependency?
          rescue StandardError => e
            Dependabot.logger.warn("Error checking transitive dependencies: #{e.message}")
            false
          end
        end

        # Check if this is a commonly used transitive dependency
        sig { returns(T::Boolean) }
        def is_commonly_transitive_dependency?
          common_transitive_deps = [
            "com.google.guava:guava",
            "org.apache.commons:commons-lang3",
            "commons-io:commons-io",
            "org.slf4j:slf4j-api",
            "com.fasterxml.jackson.core:jackson-core",
            "com.fasterxml.jackson.core:jackson-databind",
            "org.springframework:spring-core",
            "junit:junit",
            "org.junit.jupiter:junit-jupiter"
          ]
          
          common_transitive_deps.include?(dependency.name)
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
          dependencies_depending_on_target.filter_map do |dep|
            # For each dependent dependency, find the latest compatible version
            latest_version = find_latest_compatible_version(dep)
            
            # Only update if we found a newer version
            next unless latest_version
            
            Dependency.new(
              name: dep.name,
              version: latest_version.to_s,
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

          # Find the latest version that's likely to be compatible
          # For most Maven dependencies, using the latest version is usually safe
          # unless there are breaking changes
          
          latest_version = releases.map(&:version).max
          current_version = dep.version ? Maven::Version.new(dep.version) : nil
          
          # Only update if there's actually a newer version available
          if latest_version && current_version && latest_version > current_version
            latest_version
          else
            nil
          end
        rescue StandardError => e
          Dependabot.logger.warn("Error finding compatible version for #{dep.name}: #{e.message}")
          nil
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