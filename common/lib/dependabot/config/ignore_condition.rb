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

      ALL_VERSIONS = ">= 0"

      attr_reader :dependency_name, :versions, :update_types
      def initialize(dependency_name:, versions: nil, update_types: nil)
        @dependency_name = dependency_name
        @versions = versions || []
        @update_types = update_types || []
      end

      def ignored_versions(dependency)
        return [ALL_VERSIONS] if @versions.empty? && @update_types.empty?

        versions_by_type(dependency) + @versions
      end

      private

      def effective_update_type
        UPDATE_TYPES.find { |t| @update_types.include?(t) }
      end

      def versions_by_type(dep)
        case effective_update_type
        when :ignore_patch_versions
          [ignore_version(dep.version, 3)]
        when :ignore_minor_versions
          [ignore_version(dep.version, 2)]
        when :ignore_major_versions
          [ALL_VERSIONS]
        else
          []
        end
      end

      def ignore_version(version, precision)
        parts = version.split(".")
        version_parts = parts.fill(0, parts.length...[3, precision].max).
                        first(precision)

        lower_bound = [
          *version_parts.first(precision - 1),
          "a"
        ].join(".")
        upper_bound =
          if numeric_version?(version)
            [
              *version_parts.first(precision - 2),
              version_parts[precision - 2].to_i + 1
            ].join(".")
          else
            [
              *version_parts.first(precision - 1),
              version_parts[precision - 1].to_i + 999_999
            ].join(".")
          end

        ">= #{lower_bound}, < #{upper_bound}"
      end

      def numeric_version?(version)
        return false if version == ""

        Gem::Version.correct?(version)
      end
    end
  end
end
