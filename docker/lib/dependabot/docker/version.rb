# typed: strict
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"
require "dependabot/docker/tag"
require "sorbet-runtime"

module Dependabot
  module Docker
    # In the special case of Java, the version string may also contain
    # optional "update number" and "identifier" components.
    # See https://www.oracle.com/java/technologies/javase/versioning-naming.html
    # for a description of Java versions.
    #
    class Version < Dependabot::Version
      extend T::Sig
      # The regex has limits for the 0,255 and 1,255 repetitions to avoid infinite limits which makes codeql angry.
      # A docker image cannot be longer than 255 characters anyways.
      DOCKER_VERSION_REGEX = /^(?<prefix>[a-z._\-]{0,255})[_\-v]?(?<version>.{1,255})$/

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        parsed_version = version.to_s.match(DOCKER_VERSION_REGEX)
        release_part, update_part = T.must(T.must(parsed_version)[:version]).split("_", 2)

        # The numeric_version is needed here to validate the version string (ex: 20.9.0-alpine3.18)
        # when the call is made via Depenedabot Api to convert the image version to semver.
        release_part = Tag.new(T.must(release_part).chomp(".").chomp("-").chomp("_")).numeric_version

        @release_part = T.let(Dependabot::Version.new(release_part.tr("-", ".")), Dependabot::Version)
        @update_part = T.let(
          Dependabot::Version.new(update_part&.start_with?(/[0-9]/) ? update_part : 0),
          Dependabot::Version
        )

        super(@release_part)
      end

      sig { override.params(version: T.nilable(T.any(String, Integer, Gem::Version))).returns(T::Boolean) }
      def self.correct?(version)
        return true if version.is_a?(Gem::Version)

        # We can't call new here because Gem::Version calls self.correct? in its initialize method
        # causing an infinite loop, so instead we check if the release_part of the version is correct
        parsed_version = version.to_s.match(DOCKER_VERSION_REGEX)
        return false if parsed_version.nil?

        release_part, = T.must(parsed_version[:version]).split("_", 2)
        release_part = Tag.new(T.must(release_part).chomp(".").chomp("-").chomp("_")).numeric_version || parsed_version
        super(release_part.to_s)
      rescue ArgumentError
        # if we can't instantiate a version, it can't be correct
        false
      end

      sig { override.returns(String) }
      def to_semver
        @release_part.to_semver
      end

      sig { returns(T::Array[String]) }
      def segments
        @release_part.segments
      end

      sig { returns(Dependabot::Version) }
      attr_reader :release_part

      sig { params(other: Dependabot::Docker::Version).returns(T.nilable(Integer)) }
      def <=>(other)
        sort_criteria <=> other.sort_criteria
      end

      sig { returns(T::Array[Dependabot::Version]) }
      def sort_criteria
        [@release_part, @update_part]
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("docker", Dependabot::Docker::Version)
