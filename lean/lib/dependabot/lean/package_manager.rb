# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/lean"
require "dependabot/lean/version"

module Dependabot
  module Lean
    # Package manager for Lean
    class LeanPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "lean"
      VERSION = "1.0.0"

      sig { void }
      def initialize
        super(
          name: NAME,
          version: Lean::Version.new(VERSION),
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS
        )
      end
    end

    # Language version manager for Lean
    class LeanLanguage < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "lean"

      sig { params(raw_version: T.nilable(String)).void }
      def initialize(raw_version)
        super(
          name: NAME,
          version: raw_version ? Lean::Version.new(raw_version) : nil,
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS
        )
      end
    end
  end
end
