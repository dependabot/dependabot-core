# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dotnet_sdk/version"
require "dependabot/ecosystem"

module Dependabot
  module DotnetSdk
    class DotnetSDK < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      LANGUAGE = "DotnetSDK"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(name: LANGUAGE, version: Version.new(raw_version))
      end
    end
  end
end
