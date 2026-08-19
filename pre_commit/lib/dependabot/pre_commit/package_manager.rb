# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pre_commit/version"
require "dependabot/ecosystem"
require "dependabot/pre_commit/requirement"

module Dependabot
  module PreCommit
    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      # The package manager name for Pre-commit
      NAME = "pre_commit"

      # The version of the package manager
      VERSION = "1.0.0"

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
