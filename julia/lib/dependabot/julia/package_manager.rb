# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"

module Dependabot
  module Julia
    class PackageManager < Ecosystem::VersionManager
      extend T::Sig

      PACKAGE_MANAGER_COMMAND = T.let("julia", String)
      MINIMUM_VERSION = T.let("1.10", String)
      CURRENT_VERSION = T.let("1.11", String)

      sig { returns(T.nilable(String)) }
      def self.detected_version
        output = SharedHelpers.run_shell_command("#{PACKAGE_MANAGER_COMMAND} --version")
        version_match = output.match(/julia version (\d+\.\d+\.\d+)/)
        return version_match[1] if version_match

        raise "Failed to parse Julia version from: #{output}"
      end

      sig { void }
      def initialize
        super(
          name: "julia",
          detected_version: Version.new(self.class.detected_version),
          supported_versions: [
            Version.new(MINIMUM_VERSION),
            Version.new(CURRENT_VERSION)
          ],
          deprecated_versions: []
        )
      end
    end
  end
end
