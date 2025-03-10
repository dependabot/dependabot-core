# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"

module Dependabot
  module Helm
    ECOSYSTEM = "helm"

    SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class HelmPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "helm"

      # As helm updater is an in house custom utility, We use a placeholder
      # version number for helm updater
      VERSION = "1.0.0"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        void
      end
      def initialize
        super(
          name: NAME,
          version: Version.new(VERSION),
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS
       )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
