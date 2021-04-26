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

      # Returns array of requirement strings for versions that should be ignored
      def ignored_versions(dependency, security_updates_only)
        ignored_ranges(dependency, security_updates_only).
          reject { |v| Dependabot::Config::IgnoreCondition.sha_ignore?(v) }
      end

      # Returns true if the target version of a dependency is ignored by this condition
      def ignored?(dependency, security_updates_only, version)
        version_class = Dependabot::Utils.version_class_for_package_manager(dependency.package_manager)
        parsed_version = if version.is_a?(version_class) || version.is_a?(Gem::Version)
                           version
                         else
                           version_class.new(version)
                         end

        req_class = Dependabot::Utils.requirement_class_for_package_manager(dependency.package_manager)
        parsed_reqs = ignored_ranges(dependency, security_updates_only).
                      map do |r|
                        if Dependabot::Config::IgnoreCondition.sha_ignore?(r)
                          ShaRequirement.new(r)
                        else
                          req_class.new(r)
                        end
                      end
        parsed_reqs.any? { |r| r.satisfied_by?(parsed_version) }
      end

      # Returns true if this ignore condition is for a specific version, typically a git commit.
      def self.sha_ignore?(version_requirements)
        GIT_SHA_IGNORE_REGEX.match?(version_requirements)
      end

      private

      GIT_SHA_IGNORE_PREFIX = "!!"
      GIT_SHA_IGNORE_REGEX = /\A#{GIT_SHA_IGNORE_PREFIX}/.freeze

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

        if Gem::Version.correct?(version)
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

      def ignored_ranges(dependency, security_updates_only)
        ignored_ranges ||= {}
        key = "#{dependency.name}-#{dependency.version}-#{security_updates_only}"
        ignored_ranges[key] ||= if security_updates_only
                                  versions
                                elsif versions.empty? && transformed_update_types.empty?
                                  [ALL_VERSIONS]
                                else
                                  versions_by_type(dependency) + versions
                                end
      end

      # Custom requirement for ignoring specific git commit SHAs
      class ShaRequirement < Gem::Requirement
        def initialize(*requirements)
          requirements = requirements.flatten.flat_map do |req_string|
            req_string.split(",").map(&:strip)
          end

          super(requirements)
        end

        def self.parse(obj)
          if obj.is_a?(String) && obj.strip.match?(GIT_SHA_IGNORE_REGEX)
            return [GIT_SHA_IGNORE_PREFIX, obj.gsub(GIT_SHA_IGNORE_REGEX, "").strip]
          end

          super
        end

        def satisfied_by?(version)
          if requirements.any? { |op, _| op == GIT_SHA_IGNORE_PREFIX }
            rv = requirements.find { |op, _| op == GIT_SHA_IGNORE_PREFIX }.last
            return rv == version.to_s
          end
          super
        end
      end
    end
  end
end
