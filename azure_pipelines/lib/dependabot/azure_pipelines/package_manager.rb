# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/ecosystem"
require "dependabot/requirement"
require "dependabot/version"

module Dependabot
  module AzurePipelines
    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = T.let("azure_pipelines", String)

      VERSION = T.let("1.0.0", String)

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
