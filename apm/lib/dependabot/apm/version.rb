# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module Apm
    # APM pins dependencies to git refs. When that ref is a semver tag (e.g.
    # `v1.2.0` or `1.2.0`) we treat it as the dependency version, normalising any
    # leading `v` so `v1.2.0` and `1.2.0` compare equal.
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        version = Version.remove_leading_v(version)
        super
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Apm::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Apm::Version)
      end

      sig { params(version: VersionParameter).returns(VersionParameter) }
      def self.remove_leading_v(version)
        return version unless version.to_s.match?(/\Av?([0-9])/)

        version.to_s.sub(/\Av?/, "")
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.to_s.strip.empty?

        super(remove_leading_v(version))
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("apm", Dependabot::Apm::Version)
