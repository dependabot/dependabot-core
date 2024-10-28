# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/silent/version"
require "dependabot/ecosystem"

module Dependabot
  module Silent
    ECOSYSYEM = "silent"
    PACKAGE_MANAGER = "silent"

    SUPPORTED_SILENT_VERSIONS = T.let([Version.new("2")].freeze, T::Array[Dependabot::Version])
    DEPRECATED_SILENT_VERSIONS = T.let([Version.new("1")].freeze, T::Array[Dependabot::Version])

    class PackageManager < Ecosystem::VersionManager
      extend T::Sig

      sig { params(version: T.any(String, Dependabot::Version)).void }
      def initialize(version)
        super(
          PACKAGE_MANAGER,
          Version.new(version),
          DEPRECATED_SILENT_VERSIONS,
          SUPPORTED_SILENT_VERSIONS,
       )
      end
    end
  end
end
