# frozen_string_literal: true

module Dependabot
  module Config
    # Filters versions that should not be considered for dependency updates
    class IgnoreCondition
      PATCH_VERSION_TYPE = "version-update:semver-patch"
      MINOR_VERSION_TYPE = "version-update:semver-minor"
      MAJOR_VERSION_TYPE = "version-update:semver-major"

      ALL_VERSIONS = ">= 0"

      attr_reader :dependency_name, :versions, :update_types

      def initialize(dependency_name:, versions: nil, update_types: nil)
        @dependency_name = dependency_name
        @versions = versions || []
        @update_types = update_types || []
      end

      def ignored_versions(dependency, security_updates_only)
        return versions if security_updates_only
        return [ALL_VERSIONS] if versions.empty? && transformed_update_types.empty?

        versions_by_type(dependency) + versions
      end

      private

      def transformed_update_types
        update_types.map(&:downcase).map(&:strip).compact
      end

      def versions_by_type(dependency)
        transformed_update_types.flat_map do |t|
          case t
          when PATCH_VERSION_TYPE
            ignore_patch(dependency.version)
          when MINOR_VERSION_TYPE
            ignore_minor(dependency.version)
          when MAJOR_VERSION_TYPE
            ignore_major(dependency.version)
          else
            []
          end
        end.compact
      end

      def ignore_patch(version)
        parts = version.split(".")
        version_parts = parts.fill(0, parts.length...4)
        lower_parts = if numeric_version?(version)
                        version_parts.first(3) + [version_parts[3].to_i + 1] + ["a"]
                      else
                        version_parts.first(2) + [version_parts[2].to_i + 1] + ["a"]
                      end
        upper_parts = if numeric_version?(version)
                        version_parts.first(1) + [version_parts[1].to_i + 1]
                      else
                        version_parts.first(2) + [version_parts[2].to_i + 999_999]
                      end
        lower_bound = ">= #{lower_parts.join('.')}"
        upper_bound = "< #{upper_parts.join('.')}"
        ["#{lower_bound}, #{upper_bound}"]
      end

      def ignore_minor(version)
        parts = version.split(".")
        version_parts = parts.fill(0, parts.length...3)
        lower_parts = if numeric_version?(version)
                        version_parts.first(1) + [version_parts[1].to_i + 1] + ["a"]
                      else
                        version_parts.first(1) + ["a"]
                      end
        upper_parts = if numeric_version?(version)
                        version_parts.first(0) + [version_parts[0].to_i + 1]
                      else
                        version_parts.first(1) + [version_parts[1].to_i + 999_999]
                      end
        lower_bound = ">= #{lower_parts.join('.')}"
        upper_bound = "< #{upper_parts.join('.')}"
        ["#{lower_bound}, #{upper_bound}"]
      end

      def ignore_major(version)
        parts = version.split(".")
        version_parts = parts.fill(0, parts.length...2)
        lower_parts = if numeric_version?(version)
                        [version_parts[0].to_i + 1] + ["a"]
                      else
                        version_parts.first(1) + [999_999]
                      end
        upper_parts = if numeric_version?(version)
                        [version_parts[0].to_i + 2]
                      else
                        [999_999]
                      end
        lower_bound = ">= #{lower_parts.join('.')}"
        upper_bound = "< #{upper_parts.join('.')}"
        ["#{lower_bound}, #{upper_bound}"]
      end

      def numeric_version?(version)
        return false if version.nil? || version.empty?

        Gem::Version.correct?(version)
      end
    end
  end
end
