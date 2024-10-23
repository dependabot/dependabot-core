# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/silent/version"
require "dependabot/ecosystem"

module Dependabot
  module Silent
    PACKAGE_MANAGER = "silent"

    SUPPORTED_SILENT_VERSIONS = T.let([Version.new("2")].freeze, T::Array[Dependabot::Version])
    DEPRECATED_SILENT_VERSIONS = T.let([Version.new("1")].freeze, T::Array[Dependabot::Version])

    class PackageManager < Ecosystem::VersionManager
      extend T::Sig

      sig { params(version: T.any(String, Dependabot::Version)).void }
      def initialize(version)
        @version = T.let(Version.new(version), Dependabot::Version)
        @name = T.let(PACKAGE_MANAGER, String)
        @deprecated_versions = T.let(DEPRECATED_SILENT_VERSIONS, T::Array[Dependabot::Version])
        @supported_versions = T.let(SUPPORTED_SILENT_VERSIONS, T::Array[Dependabot::Version])
      end

      sig { override.returns(String) }
      attr_reader :name

      sig { override.returns(Dependabot::Version) }
      attr_reader :version

      sig { override.returns(T::Array[Dependabot::Version]) }
      attr_reader :deprecated_versions

      sig { override.returns(T::Array[Dependabot::Version]) }
      attr_reader :supported_versions

      sig { override.returns(T::Boolean) }
      def unsupported?
        # Check if the version is not supported
        supported_versions.all? { |supported| supported > version }
      end
    end
  end
end
