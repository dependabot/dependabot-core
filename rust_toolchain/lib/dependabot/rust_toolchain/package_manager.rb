# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/ecosystem"

require "dependabot/rust_toolchain/requirement"
require "dependabot/rust_toolchain/version"

module Dependabot
  module RustToolchain
    class RustToolchainPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      # This is a placeholder version for the package manager.
      VERSION = "1.0.0"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        void
      end
      def initialize
        super(
          name: PACKAGE_MANAGER,
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
