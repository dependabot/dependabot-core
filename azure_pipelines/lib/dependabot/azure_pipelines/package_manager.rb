# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/ecosystem"

require "dependabot/azure_pipelines/constants"

module Dependabot
  module AzurePipelines
    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { void }
      def initialize
        super(name: PACKAGE_MANAGER)
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
