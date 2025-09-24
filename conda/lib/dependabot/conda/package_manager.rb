# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/conda/version"

module Dependabot
  module Conda
    ECOSYSTEM = "conda"

    SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
    DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class CondaPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "conda"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig { void }
      def initialize
        super(
          name: NAME,
          version: nil,
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
