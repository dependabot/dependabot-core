# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/shared_helpers"
require "dependabot/version"

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
      rescue StandardError => e # Catch StandardError from run_shell_command
        Dependabot.logger.error("Error detecting Julia version: #{e.message}")
        raise "Failed to parse Julia version" # Re-raise with the expected message
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

      sig { returns(T.nilable(Dependabot::Version)) }
      def version
        @version ||= Dependabot::Version.new(detected_version)
      end

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def ecosystem
        {
          package_manager: "julia",
          version: version
        }
      end

      private

      sig { returns(T.nilable(Dependabot::Version)) }
      def detected_version
        command = "julia -v"
        output = SharedHelpers.run_shell_command(command)
        version_regex = /julia version (\d+\.\d+\.\d+)/
        match = output.match(version_regex)

        raise "Failed to parse Julia version" unless match

        Dependabot::Version.new(match[1])
      rescue StandardError
        raise "Failed to parse Julia version"
      end
    end
  end
end
