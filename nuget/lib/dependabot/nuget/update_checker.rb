# typed: strict
# frozen_string_literal: true

require "dependabot/nuget/file_parser"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/version_finder"
      require_relative "update_checker/property_updater"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/dependency_finder"

      PROPERTY_REGEX = /\$\((?<property>.*?)\)/

      sig { override.returns(T.nilable(String)) }
      def latest_version
        # No need to find latest version for transitive dependencies unless they have a vulnerability.
        return dependency.version if !dependency.top_level? && !vulnerable?

        # if no update sources have the requisite package, then we can only assume that the current version is correct
        @latest_version = T.let(
          latest_version_details&.fetch(:version)&.to_s || dependency.version,
          T.nilable(String)
        )
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # We always want a full unlock since any package update could update peer dependencies as well.
        # To force a full unlock instead of an own unlock, we return nil.
        nil
      end

      sig { override.returns(Dependabot::Nuget::Version) }
      def lowest_security_fix_version
        lowest_security_fix_version_details&.fetch(:version)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        return nil if version_comes_from_multi_dependency_property?

        lowest_security_fix_version
      end

      sig { override.returns(NilClass) }
      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Nuget has a single dependency file
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version_details&.fetch(:version, nil)&.to_s,
          source_details: preferred_resolvable_version_details&.slice(:nuspec_url, :repo_url, :source_url)
        ).updated_requirements
      end

      sig { returns(T::Boolean) }
      def up_to_date?
        # No need to update transitive dependencies unless they have a vulnerability.
        return true if !dependency.top_level? && !vulnerable?

        # If any requirements have an uninterpolated property in them then
        # that property couldn't be found, and we assume that the dependency
        # is up-to-date
        return true unless requirements_unlocked_or_can_be?

        super
      end

      sig { returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        # If any requirements have an uninterpolated property in them then
        # that property couldn't be found, and the requirement therefore
        # cannot be unlocked (since we can't update that property)
        dependency.requirements.none? do |req|
          req.fetch(:requirement)&.match?(PROPERTY_REGEX)
        end
      end

      private

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def preferred_resolvable_version_details
        # If this dependency is vulnerable, prefer trying to update to the
        # lowest_resolvable_security_fix_version. Otherwise update all the way
        # to the latest_resolvable_version.
        return lowest_security_fix_version_details if vulnerable?

        latest_version_details
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # We always want a full unlock since any package update could update peer dependencies as well.
        return true unless version_comes_from_multi_dependency_property?

        property_updater.update_possible?
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        return property_updater.updated_dependencies if version_comes_from_multi_dependency_property?

        puts "Finding updated dependencies for #{dependency.name}."

        updated_dependency = Dependency.new(
          name: dependency.name,
          version: latest_version,
          requirements: updated_requirements,
          previous_version: dependency.version,
          previous_requirements: dependency.requirements,
          package_manager: dependency.package_manager
        )
        updated_dependencies = [updated_dependency]
        updated_dependencies += DependencyFinder.new(
          dependency: updated_dependency,
          dependency_files: dependency_files,
          ignored_versions: ignored_versions,
          credentials: credentials,
          repo_contents_path: @repo_contents_path
        ).updated_peer_dependencies
        updated_dependencies
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def preferred_version_details
        return lowest_security_fix_version_details if vulnerable?

        latest_version_details
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def latest_version_details
        @latest_version_details ||=
          T.let(
            version_finder.latest_version_details,
            T.nilable(T::Hash[Symbol, T.untyped])
          )
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def lowest_security_fix_version_details
        @lowest_security_fix_version_details ||=
          T.let(
            version_finder.lowest_security_fix_version_details,
            T.nilable(T::Hash[Symbol, T.untyped])
          )
      end

      sig { returns(Dependabot::Nuget::UpdateChecker::VersionFinder) }
      def version_finder
        @version_finder ||=
          T.let(
            VersionFinder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: @raise_on_ignored,
              security_advisories: security_advisories,
              repo_contents_path: @repo_contents_path
            ),
            T.nilable(Dependabot::Nuget::UpdateChecker::VersionFinder)
          )
      end

      sig { returns(Dependabot::Nuget::UpdateChecker::PropertyUpdater) }
      def property_updater
        @property_updater ||=
          T.let(
            PropertyUpdater.new(
              dependency: dependency,
              dependency_files: dependency_files,
              target_version_details: latest_version_details,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: @raise_on_ignored,
              repo_contents_path: @repo_contents_path
            ),
            T.nilable(Dependabot::Nuget::UpdateChecker::PropertyUpdater)
          )
      end

      sig { returns(T::Boolean) }
      def version_comes_from_multi_dependency_property?
        declarations_using_a_property.any? do |requirement|
          property_name = requirement.fetch(:metadata).fetch(:property_name)

          all_property_based_dependencies.any? do |dep|
            next false if dep.name == dependency.name

            dep.requirements.any? do |req|
              req.dig(:metadata, :property_name) == property_name
            end
          end
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def declarations_using_a_property
        @declarations_using_a_property ||=
          T.let(
            dependency.requirements
                      .select { |req| req.dig(:metadata, :property_name) },
            T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
          )
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def all_property_based_dependencies
        @all_property_based_dependencies ||=
          T.let(
            Nuget::FileParser.new(
              dependency_files: dependency_files,
              repo_contents_path: repo_contents_path,
              source: nil
            ).parse.select do |dep|
              dep.requirements.any? { |req| req.dig(:metadata, :property_name) }
            end,
            T.nilable(T::Array[Dependabot::Dependency])
          )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("nuget", Dependabot::Nuget::UpdateChecker)
