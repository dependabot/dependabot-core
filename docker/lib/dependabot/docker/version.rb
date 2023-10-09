# typed: true
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Docker
    # In the special case of Java, the version string may also contain
    # optional "update number" and "identifier" components.
    # See https://www.oracle.com/java/technologies/javase/versioning-naming.html
    # for a description of Java versions.
    #
    class Version < Dependabot::Version
      SHA_REGEX = /[0-9a-f]{64}/.freeze
      STRING_REGEX = /^[a-zA-Z]+$/.freeze

      def initialize(version)
        if version.to_s.match?(SHA_REGEX) || version.to_s.match?(STRING_REGEX)
          @release_part = version
          @update_part = 0
          return @release_part
        end

        release_part, update_part = version.split("_", 2)

        @release_part = Dependabot::Version.new(release_part.sub("v", "").tr("-", "."))
        @update_part = Dependabot::Version.new(update_part&.start_with?(/[0-9]/) ? update_part : 0)

        super(@release_part)
      end

      def self.correct?(version)
        return true if version.is_a?(Gem::Version)
        return true if version.to_s.match?(SHA_REGEX)
        return true if version.to_s.match?(STRING_REGEX)

        # We can't call new here because Gem::Version calls self.correct? in its initialize method
        # causing an infinite loop, so instead we check if the release_part of the version is correct
        release_part, = version.split("_", 2)
        release_part = release_part.sub("v", "").tr("-", ".")
        super(release_part)
      rescue ArgumentError
        # if we can't instantiate a version, it can't be correct
        false
      end

      def to_semver
        return @release_part if @release_part.to_s.match?(SHA_REGEX)
        return @release_part if @release_part.to_s.match?(STRING_REGEX)
        @release_part.to_semver
      end

      def segments
        return [@release_part] if @release_part.to_s.match?(SHA_REGEX)
        return [@release_part] if @release_part.to_s.match?(STRING_REGEX)
        @release_part.segments
      end

      attr_reader :release_part

      def <=>(other)
        sort_criteria <=> other.sort_criteria
      end

      def sort_criteria
        [@release_part, @update_part]
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("docker", Dependabot::Docker::Version)
