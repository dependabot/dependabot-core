# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module GithubActions
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        version = Version.remove_leading_v(version)
        super
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::GithubActions::Version) }
      def self.new(version)
        T.cast(super, Dependabot::GithubActions::Version)
      end

      sig { params(version: VersionParameter).returns(VersionParameter) }
      def self.remove_leading_v(version)
        str = version.to_s.split("/").last || "" # drop a leading path segment
        return str if str.match?(/\A\d/) # already a bare version
        return T.must(str[1..]) if str.match?(/\Av\d/) # leading "v1.2.3"

        # An action-name prefix precedes the version (e.g. "resolve-gh-token-v2.1.0", or
        # "cache-v2-helper-v1.0.0" whose name itself contains "-v2"). The version begins at the
        # first "-v" with a dotted core; fall back to the last "-v" for moving-major tags ("...-v2").
        last = T.let(nil, T.nilable(Integer))
        offset = 0
        while (i = str.index(/-v\d/, offset))
          core = T.must(str[(i + 2)..])
          return core if core.match?(/\A\d+\.\d/)

          last = i
          offset = i + 2
        end
        last ? T.must(str[(last + 2)..]) : str
      end

      sig { params(version: VersionParameter).returns(T::Boolean) }
      def self.path_based?(version)
        str = version.to_s
        idx = str.rindex("/")
        return false if idx.nil? || idx.zero? # needs a non-empty path prefix before "/"

        T.must(str[(idx + 1)..]).match?(/\Av?[0-9]/)
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.to_s.strip.empty?

        version = Version.remove_leading_v(version)
        super
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("github_actions", Dependabot::GithubActions::Version)
