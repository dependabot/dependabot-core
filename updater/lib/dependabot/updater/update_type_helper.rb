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
        params(
          prev: Dependabot::Version,
          curr: Dependabot::Version,
          semantic_versioning: String
        ).returns(T.nilable(String))
      end
      def classify_semver_update(prev, curr, semantic_versioning: "relaxed")
        prev_parts = semver_parts(prev)
        curr_parts = semver_parts(curr)
        return nil if prev_parts.nil? || curr_parts.nil?

        return classify_strict_semver(prev_parts, curr_parts) if semantic_versioning == "strict"

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

      sig { params(prev_parts: SemverParts, curr_parts: SemverParts).returns(T::Boolean) }
      def zero_zero_version_changed?(prev_parts, curr_parts)
        prev_parts.major.zero? && prev_parts.minor.zero? &&
          (curr_parts.minor > prev_parts.minor || curr_parts.patch > prev_parts.patch)
      end

      # Strict semver classification for 0.x versions:
      # - 0.0.z → any change is major
      # - 0.y.z → minor change is major, patch change is patch
      sig { params(prev_parts: SemverParts, curr_parts: SemverParts).returns(T.nilable(String)) }
      def classify_strict_semver(prev_parts, curr_parts)
        # Major version increase is always major
        return "major" if curr_parts.major > prev_parts.major

        # For 0.0.z versions, any change is breaking
        return "major" if zero_zero_version_changed?(prev_parts, curr_parts)

        # For 0.y.z versions (y > 0), minor changes are breaking
        if prev_parts.major.zero?
          return "major" if curr_parts.minor > prev_parts.minor
          return "patch" if curr_parts.patch > prev_parts.patch
        end

        # Standard semver for >= 1.0.0
        return "minor" if curr_parts.minor > prev_parts.minor
        return "patch" if curr_parts.patch > prev_parts.patch

        Dependabot.logger.info(
          "Could not classify strict semver update: #{prev_parts.major}.#{prev_parts.minor}.#{prev_parts.patch} -> " \
          "#{curr_parts.major}.#{curr_parts.minor}.#{curr_parts.patch}"
        )
        nil
      end

      sig { params(version: T.untyped).returns(T.nilable(SemverParts)) }
      def semver_parts(version)
        # Normalize the version string by stripping any 'v' prefix
        normalized_version = version.to_s.delete_prefix("v")

        if version.respond_to?(:semver_parts)
          parts = version.semver_parts
          return SemverParts.new(major: parts[0], minor: parts[1], patch: parts[2]) if parts
        end

        # Parse the normalized version string into numeric segments
        segments = normalized_version.split(".").filter_map do |segment|
          segment.to_i if segment.match?(/^\d+$/)
        end

        return nil if segments.empty?

        major = segments[0] || 0
        minor = segments[1] || 0
        patch = segments[2] || 0

        Dependabot.logger.info(
          "Extracted semver parts from version #{version}: major=#{major}, minor=#{minor}, patch=#{patch}"
        )

        SemverParts.new(major: major, minor: minor, patch: patch)
      end
    end
  end
end
