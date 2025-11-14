# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module Opentofu
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        version = Version.remove_leading_v(version)
        version = Version.remove_backport(version)

        super
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Opentofu::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Opentofu::Version)
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        version = Version.remove_leading_v(version)
        version = Version.remove_backport(version)

        return false if version.to_s.strip.empty?

        super
      end

      sig { params(version: VersionParameter).returns(VersionParameter) }
      def self.remove_leading_v(version)
        return version.gsub(/^v/, "") if version.is_a?(String)

        version
      end

      sig { params(version: VersionParameter).returns(VersionParameter) }
      def self.remove_backport(version)
        return version.split("+").first if version.is_a?(String) && version.include?("+")

        version
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("opentofu", Dependabot::Opentofu::Version)
