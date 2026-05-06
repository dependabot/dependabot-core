# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/sbt/file_parser"
require "dependabot/sbt/file_parser/property_value_finder"

module Dependabot
  module Sbt
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_finder"

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_version
        latest_version_details&.fetch(:version)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version
        # SBT has no transitive dependency resolution constraints in manifest files.
        # Return nil if version comes from a multi-dependency property (needs full unlock).
        return nil if version_comes_from_multi_dependency_property?

        latest_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        lowest_security_fix_version_details&.fetch(:version)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        return nil if version_comes_from_multi_dependency_property?

        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        # SBT uses exact versions in build files, so no constraint resolution needed.
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        property_names =
          declarations_using_a_property
          .filter_map { |req| req.dig(:metadata, :property_name) }

        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version&.to_s,
          source_url: preferred_version_details&.fetch(:source_url),
          properties_to_update: property_names
        ).updated_requirements
      end

      sig { override.returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        # If any requirement uses a val we couldn't resolve, we can't update
        !dependency.version&.include?("${")
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        return false unless version_comes_from_multi_dependency_property?

        # Full unlock via property updates can be added later
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        []
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
        @version_finder ||= T.let(
          VersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            cooldown_options: update_cooldown,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          ),
          T.nilable(VersionFinder)
        )
      end

      sig { returns(T::Boolean) }
      def version_comes_from_multi_dependency_property?
        declarations_using_a_property.any? do |requirement|
          property_name = requirement.dig(:metadata, :property_name)
          property_source = requirement.dig(:metadata, :property_source)

          next false unless property_name

          all_property_based_dependencies.any? do |dep|
            next false if dep.name == dependency.name

            dep.requirements.any? do |req|
              next unless req.dig(:metadata, :property_name) == property_name

              req.dig(:metadata, :property_source) == property_source
            end
          end
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def declarations_using_a_property
        @declarations_using_a_property ||= T.let(
          dependency.requirements
                    .select { |req| req.dig(:metadata, :property_name) },
          T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
        )
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def all_property_based_dependencies
        @all_property_based_dependencies ||= T.let(
          Sbt::FileParser.new(
            dependency_files: dependency_files,
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

Dependabot::UpdateCheckers.register("sbt", Dependabot::Sbt::UpdateChecker)
