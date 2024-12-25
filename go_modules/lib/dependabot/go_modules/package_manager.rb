# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/go_modules/version"
require "dependabot/go_modules/requirement"

module Dependabot
  module GoModules
    ECOSYSTEM = "go"
    PACKAGE_MANAGER = "go_modules"
    SUPPORTED_GO_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    # When a version is going to be unsupported, it will be added here
    DEPRECATED_GO_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          PACKAGE_MANAGER,
          nil,
          Version.new(raw_version),
          DEPRECATED_GO_VERSIONS,
          SUPPORTED_GO_VERSIONS
        )
      end

      sig { returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
