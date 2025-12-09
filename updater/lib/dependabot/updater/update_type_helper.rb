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
          Dependabot.logger.debug(
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

        prev_major, prev_minor, prev_patch = prev_parts
        curr_major, curr_minor, curr_patch = curr_parts

        return "major" if curr_major > prev_major
        return "minor" if curr_major == prev_major && curr_minor > prev_minor
        return "patch" if curr_major == prev_major && curr_minor == prev_minor && curr_patch > prev_patch

        nil
      end

      sig { params(version: T.untyped).returns(T.nilable([Integer, Integer, Integer])) }
      def semver_parts(version)
        if version.respond_to?(:semver_parts)
          parts = version.semver_parts
          return parts if parts
        end

        return nil unless version.respond_to?(:segments)

        segments = version.segments
        return nil unless segments.is_a?(Array)

        major = segments[0] || 0
        minor = segments[1] || 0
        patch = segments[2] || 0

        [major, minor, patch]
      end
    end
  end
end
