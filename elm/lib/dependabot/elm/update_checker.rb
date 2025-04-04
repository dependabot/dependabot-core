# typed: strict
# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/registry_client"
require "dependabot/errors"

module Dependabot
  module Elm
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/elm_19_version_resolver"

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_version
        @latest_version ||= T.let(candidate_versions.max, T.nilable(Dependabot::Version))
      end

      # Overwrite the base class to allow multi-dependency update PRs for
      # dependencies for which we don't have a version.
      sig { override.params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def can_update?(requirements_to_unlock:)
        if dependency.appears_in_lockfile?
          version_can_update?(requirements_to_unlock: requirements_to_unlock)
        elsif requirements_to_unlock == :none
          false
        elsif requirements_to_unlock == :own
          requirements_can_update?
        elsif requirements_to_unlock == :all
          updated_dependencies_after_full_unlock.any?
        else
          false
        end
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version
        @latest_resolvable_version ||= T.let(
          version_resolver
          .latest_resolvable_version(unlock_requirement: :own), T.nilable(Dependabot::Version)
        )
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Elm has a single dependency file (well, there's
        # also `exact-dependencies.json`, but it's not recommended that that
        # is committed).
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_resolvable_version: latest_resolvable_version
        ).updated_requirements
      end

      private

      sig { returns(Elm19VersionResolver) }
      def version_resolver
        @version_resolver ||= T.let(
          begin
            unless dependency.requirements.any? { |r| r.fetch(:file) == MANIFEST_FILE }
              raise Dependabot::DependencyFileNotResolvable, "No #{MANIFEST_FILE} found"
            end

            Elm19VersionResolver.new(
              dependency: dependency,
              dependency_files: dependency_files
            )
          end, T.nilable(Elm19VersionResolver)
        )
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        version_resolver.updated_dependencies_after_full_unlock
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        latest_version == version_resolver
                          .latest_resolvable_version(unlock_requirement: :all)
      end

      sig { returns(T::Array[Dependabot::Version]) }
      def candidate_versions
        filtered = all_versions
                   .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }

        if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(all_versions).any?
          raise AllVersionsIgnored
        end

        filtered
      end

      sig { params(versions_array: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
      def filter_lower_versions(versions_array)
        return versions_array unless current_version

        versions_array
          .select { |version| version > current_version }
      end

      sig { returns(T::Array[Dependabot::Version]) }
      def all_versions
        @all_versions ||= T.let(fetch_all_versions, T.nilable(T::Array[Dependabot::Version]))
      end

      sig { returns(T::Array[Dependabot::Version]) }
      def fetch_all_versions
        response = Dependabot::RegistryClient.get(
          url: "https://package.elm-lang.org/packages/#{dependency.name}/releases.json"
        )

        return [] unless response.status == 200

        JSON.parse(response.body)
            .keys
            .map { |v| version_class.new(v) }
            .sort
      end

      # Overwrite the base class's requirements_up_to_date? method to instead
      # check whether the latest version is allowed
      sig { override.returns(T::Boolean) }
      def requirements_up_to_date?
        return false unless latest_version

        dependency.requirements
                  .map { |r| r.fetch(:requirement) }
                  .map { |r| requirement_class.new(r) }
                  .all? { |r| r.satisfied_by?(latest_version) }
      end
    end
  end
end

Dependabot::UpdateCheckers.register("elm", Dependabot::Elm::UpdateChecker)
