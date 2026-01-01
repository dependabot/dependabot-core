# typed: strict
# frozen_string_literal: true

require "dependabot/opam/version"
require "dependabot/ecosystem"

module Dependabot
  module Opam
    ECOSYSTEM = "opam"
    PACKAGE_MANAGER = "opam"

    # OCaml opam package manager
    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          PACKAGE_MANAGER,
          Version.new(raw_version)
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
