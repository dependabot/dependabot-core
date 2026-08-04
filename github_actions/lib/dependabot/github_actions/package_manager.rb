# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/version"
require "dependabot/ecosystem"
require "dependabot/github_actions/requirement"

module Dependabot
  module GithubActions
    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      # The package manager name for GitHub Actions
      NAME = "github_actions"

      # The version of the package manager
      VERSION = "1.0.0"

      sig { void }
      def initialize
        super(
          name: NAME,
          version: Version.new(VERSION)
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
