# frozen_string_literal: true

module Dependabot
  module Config
    # Filters versions that should not be considered for dependency updates
    class IgnoreCondition
      UPDATE_TYPES = %i(
        ignore_major_versions
        ignore_minor_versions
        ignore_patch_versions
      ).freeze

      attr_reader :dependency_name, :versions, :update_types
      def initialize(dependency_name:, versions: nil, update_types: nil)
        @dependency_name = dependency_name
        @versions = versions || []
        @update_types = update_types || []
      end

      def ignored_versions(dependency)
        versions_by_type(dependency) + @versions
      end

      private

      def versions_by_type(dep)
        case @update_types.first # FIXME: flatmap
        when :ignore_patch_versions
          [ignore_version(dep.version, 4)]
        when :ignore_minor_versions
          [ignore_version(dep.version, 3)]
        when :ignore_major_versions
          [ignore_version(dep.version, 2)]
        else
          []
        end
      end

      def ignore_version(version, precision)
        parts = version.split(".")
        version_parts = parts.fill(0, parts.length...[3, precision].max).
                        first(precision)

        lower_bound = [
          *version_parts.first(precision - 2),
          "a"
        ].join(".")
        upper_bound = [
          *version_parts.first(precision - 2),
          version_parts[precision - 2].to_i + 1
        ].join(".")

        ">= #{lower_bound}, < #{upper_bound}"
      end
    end
  end
end
