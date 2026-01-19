# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/utils"

module Dependabot
  class Updater
    # UpdateTypeHelper provides utilities for determining the update type (major, minor, patch)
    # of a dependency change. It works with different version class implementations across
    # ecosystems and provides fallback semantic versioning detection.
    module UpdateTypeHelper
      extend T::Sig

      # Represents semantic version components (major, minor, patch)
      class SemverParts < T::Struct
        const :major, Integer
        const :minor, Integer
        const :patch, Integer
      end

      sig { params(dep: Dependabot::Dependency).returns(T.nilable(T.class_of(Dependabot::Version))) }
      def version_class_for(dep)
        return nil unless dep.respond_to?(:package_manager)

        Dependabot::Utils.version_class_for_package_manager(dep.package_manager)
      end

      sig { params(version_class: T.untyped, prev_str: String, curr_str: String).returns(T.nilable(String)) }
      def update_type_from_class(version_class, prev_str, curr_str)
        return unless version_class.respond_to?(:update_type)

        result = version_class.update_type(prev_str, curr_str)
        if result.nil?
          Dependabot.logger.info(
            "Version class #{version_class} could not determine update type for #{prev_str} -> #{curr_str}"
          )
        end
        result
      end

      sig do
        params(version_class: T.untyped, prev_str: String, curr_str: String)
          .returns(T.nilable([Dependabot::Version, Dependabot::Version]))
      end
      def build_versions(version_class, prev_str, curr_str)
        return nil unless version_class.respond_to?(:correct?)
        return nil unless version_class.correct?(prev_str) && version_class.correct?(curr_str)

        [version_class.new(prev_str), version_class.new(curr_str)]
      end

      sig do
        params(prev: Dependabot::Version, curr: Dependabot::Version).returns(T.nilable(String))
      end
      def classify_semver_update(prev, curr)
        prev_parts = semver_parts(prev)
        curr_parts = semver_parts(curr)
        return nil if prev_parts.nil? || curr_parts.nil?

        return "major" if curr_parts.major > prev_parts.major
        return "minor" if curr_parts.major == prev_parts.major && curr_parts.minor > prev_parts.minor
        return "patch" if curr_parts.major == prev_parts.major &&
                          curr_parts.minor == prev_parts.minor &&
                          curr_parts.patch > prev_parts.patch

        Dependabot.logger.info(
          "Could not classify semver update: #{prev_parts.major}.#{prev_parts.minor}.#{prev_parts.patch} -> " \
          "#{curr_parts.major}.#{curr_parts.minor}.#{curr_parts.patch}"
        )
        nil
      end

      sig { params(version: T.untyped).returns(T.nilable(SemverParts)) }
      def semver_parts(version)
        if version.respond_to?(:semver_parts)
          parts = version.semver_parts
          return SemverParts.new(major: parts[0], minor: parts[1], patch: parts[2]) if parts
        end

        return nil unless version.respond_to?(:segments)

        segments = version.segments
        return nil unless segments.is_a?(Array)

        # Skip leading non-numeric segments (e.g., "v" prefix in "v1.0.0")
        numeric_segments = segments.drop_while { |s| !numeric_segment?(s) }
        return nil if numeric_segments.empty?

        major = to_integer(numeric_segments[0]) || 0
        minor = to_integer(numeric_segments[1]) || 0
        patch = to_integer(numeric_segments[2]) || 0

        SemverParts.new(major: major, minor: minor, patch: patch)
      end

      sig { params(segment: T.untyped).returns(T::Boolean) }
      def numeric_segment?(segment)
        return true if segment.is_a?(Integer)
        return false unless segment.is_a?(String)

        segment.match?(/^\d+$/)
      end

      sig { params(segment: T.untyped).returns(T.nilable(Integer)) }
      def to_integer(segment)
        return segment if segment.is_a?(Integer)
        return segment.to_i if segment.is_a?(String) && segment.match?(/^\d+$/)

        nil
      end
    end
  end
end
