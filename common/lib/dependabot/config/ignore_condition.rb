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

      def versions_by_type(dependency)
        @update_types.flat_map do |t|
          case t
          when :ignore_patch_versions
            ignore_patch(dependency.version)
          when :ignore_minor_versions
            ignore_minor(dependency.version)
          when :ignore_major_versions
            ignore_major(dependency.version)
          else
            []
          end
        end.compact
      end

      def ignore_patch(version)
        parts = version.split(".")
        return [] unless parts.size > 2

        lower_parts = parts.first(2) + ["a"]
        upper_parts = parts.first(2)
        upper_parts[1] = upper_parts[1].to_i + 1
        lower_bound = ">= #{lower_parts.join('.')}"
        upper_bound = "< #{upper_parts.join('.')}"
        ["#{lower_bound}, #{upper_bound}"]
      end

      def ignore_minor(version)
        parts = version.split(".")
        return [] if parts.size < 2

        if parts.size > 2
          lower_parts = parts.first(2) + ["a"]
          upper_parts = parts.first(1)
          lower_parts[1] = lower_parts[1].to_i + 1
          upper_parts[0] = upper_parts[0].to_i + 1
        else
          lower_parts = parts.first(1) + ["a"]
          upper_parts = parts.first(1)
          begin
            upper_parts[0] = Integer(upper_parts[0]) + 1
          rescue ArgumentError
            upper_parts.push(999_999)
          end
        end

        lower_bound = ">= #{lower_parts.join('.')}"
        upper_bound = "< #{upper_parts.join('.')}"
        ["#{lower_bound}, #{upper_bound}"]
      end

      def ignore_major(version)
        parts = version.split(".")
        return [] unless parts.size > 1

        lower_parts = parts.first(1) + ["a"]
        upper_parts = parts.first(1)
        lower_parts[0] = lower_parts[0].to_i + 1
        upper_parts[0] = upper_parts[0].to_i + 2
        lower_bound = ">= #{lower_parts.join('.')}"
        upper_bound = "< #{upper_parts.join('.')}"

        ["#{lower_bound}, #{upper_bound}"]
      end
    end
  end
end
