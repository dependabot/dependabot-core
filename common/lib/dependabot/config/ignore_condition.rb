# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Config
    # Filters versions that should not be considered for dependency updates
    class IgnoreCondition
      extend T::Sig

      PATCH_VERSION_TYPE = "version-update:semver-patch"
      MINOR_VERSION_TYPE = "version-update:semver-minor"
      MAJOR_VERSION_TYPE = "version-update:semver-major"

      ALL_VERSIONS = ">= 0"

      sig { returns(String) }
      attr_reader :dependency_name

      sig { returns(T::Array[String]) }
      attr_reader :versions

      sig { returns(T::Array[String]) }
      attr_reader :update_types

      sig do
        params(
          dependency_name: String,
          versions: T.any(NilClass, T::Array[String]),
          update_types: T.any(NilClass, T::Array[String])
        ).void
      end
      def initialize(dependency_name:, versions: nil, update_types: nil)
        @dependency_name = T.let(dependency_name, String)
        @versions = T.let(versions || [], T::Array[String])
        @update_types = T.let(update_types || [], T::Array[String])
      end

      sig { params(dependency: Dependency, security_updates_only: T::Boolean).returns(T::Array[String]) }
      def ignored_versions(dependency, security_updates_only)
        return versions if security_updates_only
        return [ALL_VERSIONS] if versions.empty? && transformed_update_types.empty?

        versions_by_type(dependency) + versions
      end

      private

      sig { returns(T::Array[String]) }
      def transformed_update_types
        update_types.map(&:downcase).filter_map(&:strip)
      end

      sig { params(dependency: Dependency).returns(T::Array[T.untyped]) }
      def versions_by_type(dependency)
        version = correct_version_for(dependency)
        return [] unless version

        transformed_update_types.flat_map do |t|
          case t
          when PATCH_VERSION_TYPE
            version.ignored_patch_versions
          when MINOR_VERSION_TYPE
            version.ignored_minor_versions
          when MAJOR_VERSION_TYPE
            version.ignored_major_versions
          else
            []
          end
        end.compact
      end

      sig { params(dependency: Dependency).returns(T.nilable(Version)) }
      def correct_version_for(dependency)
        version = dependency.version
        version = version_from_requirements(dependency) if version.nil? || version.empty?
        return if version.nil? || version.to_s.empty?

        version_class = version_class_for(dependency.package_manager)
        version_string = version.to_s
        return unless version_class.correct?(version_string)

        version_class.new(version_string)
      end

      sig { params(package_manager: String).returns(T.class_of(Version)) }
      def version_class_for(package_manager)
        Utils.version_class_for_package_manager(package_manager)
      rescue StandardError
        Version
      end

      sig { params(dependency: Dependency).returns(T.nilable(T.any(String, Gem::Version))) }
      def version_from_requirements(dependency)
        all_versions = extract_versions_from_requirements(dependency)
        return nil if all_versions.empty?

        # Prefer upper bounds, fall back to lower bounds
        max_version_from_upper_bounds(all_versions) || max_version_from_lower_bounds(all_versions)
      rescue StandardError
        nil
      end

      sig do
        params(dependency: Dependency)
          .returns(T::Array[{ op: String, version: T.any(String, Gem::Version) }])
      end
      def extract_versions_from_requirements(dependency)
        requirement_class = requirement_class_for(dependency.package_manager)

        dependency.requirements.filter_map { |r| r.fetch(:requirement) }
                  .flat_map { |req_str| parse_requirements(requirement_class, req_str) }
                  .flat_map(&:requirements)
                  .map { |req_array| { op: req_array.first, version: req_array.last } }
      end

      sig do
        params(
          requirement_class: T.class_of(Gem::Requirement),
          req_str: String
        ).returns(T::Array[Gem::Requirement])
      end
      def parse_requirements(requirement_class, req_str)
        # Use send to avoid Sorbet complaint about requirements_array not being on Gem::Requirement
        requirement_class.send(:requirements_array, req_str)
      end

      sig do
        params(versions: T::Array[{ op: String, version: T.any(String, Gem::Version) }])
          .returns(T.nilable(T.any(String, Gem::Version)))
      end
      def max_version_from_upper_bounds(versions)
        # Only use <= upper bounds (not <), and exclude prereleases
        # <= means "up to and including", so user could be on this version
        # < means "strictly below", so user is NOT on this version
        upper_bounds = versions.select { |v| v[:op] == "<=" }
                               .reject { |v| v[:version].respond_to?(:prerelease?) && v[:version].prerelease? }
        upper_bounds.map { |v| v[:version] }.max if upper_bounds.any?
      end

      sig do
        params(versions: T::Array[{ op: String, version: T.any(String, Gem::Version) }])
          .returns(T.nilable(T.any(String, Gem::Version)))
      end
      def max_version_from_lower_bounds(versions)
        lower_bounds = versions.reject { |v| v[:op].start_with?("<") }
        lower_bounds.map { |v| v[:version] }.max
      end

      sig { params(package_manager: String).returns(T.class_of(Gem::Requirement)) }
      def requirement_class_for(package_manager)
        Utils.requirement_class_for_package_manager(package_manager)
      rescue StandardError
        Gem::Requirement
      end
    end
  end
end
