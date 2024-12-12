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
        return if version.nil? || version.empty?

        version_class = version_class_for(dependency.package_manager)
        return unless version_class.correct?(version)

        version_class.new(version)
      end

      sig { params(package_manager: String).returns(T.class_of(Version)) }
      def version_class_for(package_manager)
        Utils.version_class_for_package_manager(package_manager)
      rescue StandardError
        Version
      end
    end
  end
end
