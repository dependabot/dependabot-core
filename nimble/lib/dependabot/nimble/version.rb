# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Nimble
    # Nimble versions are dot-separated numbers with an optional pre-release (`1.0.0-rc1`).
    # Git tags usually carry a leading `v`, which is not part of the version.
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        super(Version.remove_leading_v(version))
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Nimble::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Nimble::Version)
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        super(remove_leading_v(version))
      end

      sig { params(version: VersionParameter).returns(VersionParameter) }
      def self.remove_leading_v(version)
        return version unless version.is_a?(String)

        version.sub(/\Av(?=\d)/i, "")
      end
    end
  end
end

Dependabot::Utils.register_version_class("nimble", Dependabot::Nimble::Version)
