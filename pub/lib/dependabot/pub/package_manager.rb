# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pub/version"
require "dependabot/ecosystem"
require "dependabot/pub/requirement"

module Dependabot
  module Pub
    ECOSYSTEM = "dart"

    SUPPORTED_DART_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    DEPRECATED_DART_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PubPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "pub"
      VERSION = "0.0"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          raw_version: String
        ).void
      end
      def initialize(raw_version)
        super(
          NAME,
          Version.new(""),
          Version.new(raw_version),
          SUPPORTED_VERSIONS,
          DEPRECATED_VERSIONS
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
