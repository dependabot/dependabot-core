# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/nuget/version"
require "dependabot/ecosystem"
require "dependabot/nuget/requirement"

module Dependabot
  module Nuget
    ECOSYSTEM = "dotnet"

    SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class NugetPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "nuget"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          raw_version: T.nilable(String)
        ).void
      end
      def initialize(raw_version)
        super(
          NAME,
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
