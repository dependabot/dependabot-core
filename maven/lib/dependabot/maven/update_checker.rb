# typed: strict
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/maven/file_parser/property_value_finder"

module Dependabot
  module Maven
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_finder"
      require_relative "update_checker/property_updater"
      require_relative "update_checker/transitive_dependency_updater"

      sig do
        params(
          dependency: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          repo_contents_path: T.nilable(String),
          ignored_versions: T::Array[String],
          raise_on_ignored: T::Boolean,
          security_advisories: T::Array[Dependabot::SecurityAdvisory],
          requirements_update_strategy: T.nilable(Dependabot::RequirementsUpdateStrategy),
          dependency_group: T.nilable(Dependabot::DependencyGroup),
          update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
          options: T::Hash[Symbol, T.untyped]
        )
          .void
      end
      def initialize(dependency:, dependency_files:, credentials:,
                     repo_contents_path: nil, ignored_versions: [],
                     raise_on_ignored: false, security_advisories: [],
                     requirements_update_strategy: nil, dependency_group: nil,
                     update_cooldown: nil, options: {})
        super

        @version_finder = T.let(nil, T.nilable(VersionFinder))
        @property_updater = T.let(nil, T.nilable(PropertyUpdater))
        @transitive_dependency_updater = T.let(nil, T.nilable(TransitiveDependencyUpdater))
        @property_value_finder = T.let(nil, T.nilable(Maven::FileParser::PropertyValueFinder))
        @declarations_using_a_property = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
        @all_property_based_dependencies = T.let(nil, T.nilable(T::Array[Dependabot::Dependency]))
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_version
        latest_version_details&.fetch(:version)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version
        # Maven's version resolution algorithm is very simple: it just uses
        # the version defined "closest", with the first declaration winning
        # if two declarations are equally close. As a result, we can just
        # return that latest version unless dealing with a property dep.
        # https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html#Transitive_Dependencies
        return nil if version_comes_from_multi_dependency_property?

        latest_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        lowest_security_fix_version_details&.fetch(:version)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Maven has a single dependency file (the pom.xml).
        #
        # For completeness we ought to resolve the pom.xml and return the
        # latest version that satisfies the current constraint AND any
        # constraints placed on it by other dependencies. Seeing as we're
        # never going to take any action as a result, though, we just return
        # nil.
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        property_names =
          declarations_using_a_property
          .map { |req| req.dig(:metadata, :property_name) }

        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version&.to_s,
          source_url: preferred_version_details&.fetch(:source_url),
          properties_to_update: property_names
        ).updated_requirements
      end

      sig { override.returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        declarations_using_a_property.none? do |requirement|
          prop_name = requirement.dig(:metadata, :property_name)
          pom = dependency_files.find { |f| f.name == requirement[:file] }

          return false unless prop_name && pom

          declaration_pom_name =
            property_value_finder
            .property_details(property_name: prop_name, callsite_pom: pom)
            &.fetch(:file)

          declaration_pom_name == "remote_pom.xml"
        end
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        return true if version_comes_from_transitive_dependencies? && transitive_dependency_updater.update_possible?
        return false unless version_comes_from_multi_dependency_property?

        property_updater.update_possible?
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        return transitive_dependency_updater.updated_dependencies if version_comes_from_transitive_dependencies?

        property_updater.updated_dependencies
      end

      sig { override.returns(T::Boolean) }
      def numeric_version_up_to_date?
        return false unless version_class.correct?(dependency.version)

        super
      end

      sig { override.params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def numeric_version_can_update?(requirements_to_unlock:)
        return false unless version_class.correct?(dependency.version)

        super
      end

      sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def preferred_version_details
        return lowest_security_fix_version_details if vulnerable?

        latest_version_details
      end

      sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def latest_version_details
        version_finder.latest_version_details
      end

      sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def lowest_security_fix_version_details
        version_finder.lowest_security_fix_version_details
      end

      sig { returns(VersionFinder) }
      def version_finder
        @version_finder ||=
          VersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            cooldown_options: update_cooldown,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          )
      end

      sig { returns(PropertyUpdater) }
      def property_updater
        @property_updater ||=
          PropertyUpdater.new(
            dependency: dependency,
            dependency_files: dependency_files,
            target_version_details: latest_version_details,
            credentials: credentials,
            ignored_versions: ignored_versions,
            update_cooldown: update_cooldown
          )
      end

      sig { returns(TransitiveDependencyUpdater) }
      def transitive_dependency_updater
        @transitive_dependency_updater ||=
          TransitiveDependencyUpdater.new(
            dependency: dependency,
            dependency_files: dependency_files,
            target_version_details: latest_version_details,
            credentials: credentials,
            ignored_versions: ignored_versions,
            update_cooldown: update_cooldown
          )
      end

      sig { returns(Maven::FileParser::PropertyValueFinder) }
      def property_value_finder
        @property_value_finder ||=
          Maven::FileParser::PropertyValueFinder
          .new(dependency_files: dependency_files, credentials: credentials)
      end

      sig { returns(T::Boolean) }
      def version_comes_from_multi_dependency_property?
        declarations_using_a_property.any? do |requirement|
          property_name = requirement.fetch(:metadata).fetch(:property_name)
          property_source = requirement.fetch(:metadata)
                                       .fetch(:property_source)

          all_property_based_dependencies.any? do |dep|
            next false if dep.name == dependency.name

            dep.requirements.any? do |req|
              next unless req.dig(:metadata, :property_name) == property_name

              req.dig(:metadata, :property_source) == property_source
            end
          end
        end
      end

      sig { returns(T::Boolean) }
      def version_comes_from_transitive_dependencies?
        # Enable transitive dependency updates when:
        # 1. Maven transitive dependencies experiment is enabled
        # 2. Not using property-based versioning to avoid conflicts
        # 3. There are actually dependencies that depend on this one
        
        return false unless Dependabot::Experiments.enabled?(:maven_transitive_dependencies)
        return false if version_comes_from_multi_dependency_property?
        return false unless declarations_using_a_property.empty?
        
        # Check if there are dependencies that depend on our target
        transitive_dependency_updater.dependencies_depending_on_target.any?
      rescue StandardError => e
        Dependabot.logger.warn("Error checking for transitive dependencies: #{e.message}")
        false
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def declarations_using_a_property
        @declarations_using_a_property ||=
          dependency.requirements
                    .select { |req| req.dig(:metadata, :property_name) }
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def all_property_based_dependencies
        @all_property_based_dependencies ||=
          Maven::FileParser.new(
            dependency_files: dependency_files,
            source: nil
          ).parse.select do |dep|
            dep.requirements.any? { |req| req.dig(:metadata, :property_name) }
          end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("maven", Dependabot::Maven::UpdateChecker)
