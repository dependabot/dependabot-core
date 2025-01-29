# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dotnet_sdk/version"
require "dependabot/ecosystem"
require "dependabot/dotnet_sdk/requirement"

module Dependabot
  module DotnetSdk
    ECOSYSTEM = "dotnet-sdk"

    SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class DotNetSdkPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "dotnet_sdk"

      # we are not using any native helper or 3rd party utility for package manager,
      # So we supply a placeholder version with for our package manager
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
