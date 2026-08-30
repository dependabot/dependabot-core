# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/ecosystem"
require "dependabot/powershell/version"

module Dependabot
  module Powershell
    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "powershell"
      VERSION = "1.0.0"

      sig { void }
      def initialize
        super(name: NAME, version: Version.new(VERSION))
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
