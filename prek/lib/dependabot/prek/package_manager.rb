# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/prek/version"
require "dependabot/prek/requirement"

module Dependabot
  module Prek
    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      # The package manager name for prek
      NAME = T.let("prek", String)

      # The version of the package manager
      VERSION = T.let("1.0.0", String)

      sig { void }
      def initialize
        super(
          name: NAME,
          version: Version.new(VERSION)
      )
      end
    end
  end
end
