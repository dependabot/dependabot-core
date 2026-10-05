# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/ecosystem"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/version"

module Dependabot
  module KotlinToolchain
    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      MINIMUM_SUPPORTED_VERSION = "0.11.0"

      sig { params(detected_version: String).void }
      def initialize(detected_version:)
        version = Version.new(detected_version)
        super(
          name: PACKAGE_MANAGER,
          detected_version: version,
          version: version,
          deprecated_versions: [],
          supported_versions: [Version.new(MINIMUM_SUPPORTED_VERSION)]
        )
      end

      # Published wrappers are mostly pre-release builds such as 0.11.0-dev-12,
      # which Maven ordering places below the 0.11.0 release they belong to.
      sig { override.returns(T::Boolean) }
      def unsupported?
        release_version < Version.new(MINIMUM_SUPPORTED_VERSION)
      end

      private

      sig { returns(Dependabot::Version) }
      def release_version
        raw = T.must(detected_version).to_s
        Version.new(raw[/\A\d+(?:\.\d+)*/] || raw)
      end
    end
  end
end
