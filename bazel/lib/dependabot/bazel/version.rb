# typed: strict
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Bazel
    class Version < Dependabot::Version
      extend T::Sig

      VERSION_PATTERN = T.let(/^v?(\d+(?:\.\d+)*(?:[-.]?(?:alpha|beta|rc|pre|dev|snapshot)\d*)?(?:\+[a-zA-Z0-9\-_.]+)?)$/i.freeze, Regexp)

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(VERSION_PATTERN)
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)

        # Normalize the version string (remove 'v' prefix if present)
        normalized_version = @version_string.sub(/^v/, "")

        super(normalized_version)
      end

      sig { returns(String) }
      def to_s
        @version_string
      end

      sig { params(other: T.untyped).returns(T.nilable(Integer)) }
      def <=>(other)
        return nil unless other.is_a?(Dependabot::Version)

        version_without_prefix = @version_string.sub(/^v/, "")
        other_version_without_prefix = other.to_s.sub(/^v/, "")

        # Handle semantic versioning comparison using Gem::Version
        Gem::Version.new(version_without_prefix) <=>
          Gem::Version.new(other_version_without_prefix)
      end

      sig { override.returns(String) }
      def inspect
        "#<#{self.class} #{@version_string}>"
      end

      private

      sig { returns(String) }
      attr_reader :version_string
    end
  end
end
