# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/gradle/version"

module Dependabot
  module Gradle
    ECOSYSTEM = "gradle"
    PACKAGE_MANAGER = "gradle"

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { void }
      def initialize
        super(PACKAGE_MANAGER)
      end
    end
  end
end
