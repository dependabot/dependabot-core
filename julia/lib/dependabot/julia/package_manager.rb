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
      # Julia versions as of June 2025:
      # - 1.10 is the LTS (Long Term Support) version
      # - 1.11 is the current stable version
      # Update these constants when new LTS or major versions are released
      MINIMUM_VERSION = T.let("1.10", String) # LTS version
      CURRENT_VERSION = T.let("1.11", String) # Current stable version

      sig { returns(T.nilable(String)) }
      def self.detected_version
        # Try to detect Julia version by executing `julia --version`
        output = T.let(
          Dependabot::SharedHelpers.run_shell_command("julia --version"),
          String
        )

        # Parse output like "julia version 1.10.0" or "julia version 1.6.7"
        version_match = output.match(/julia version (\d+\.\d+(?:\.\d+)?)/)
        return version_match[1] if version_match

        # If we can't parse the version, log and fallback
        Dependabot.logger.warn("Could not parse Julia version from output: #{output}")
        MINIMUM_VERSION
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.info("Julia not found or failed to execute: #{e.message}")
        MINIMUM_VERSION
      rescue StandardError => e
        Dependabot.logger.error("Error detecting Julia version: #{e.message}")
        MINIMUM_VERSION
      end

      sig { void }
      def initialize
        detected_ver_str = self.class.detected_version
        # detected_version always returns a string (either detected or MINIMUM_VERSION fallback),
        # so we can safely use T.must here
        super(
          name: "julia",
          detected_version: Dependabot::Version.new(T.must(detected_ver_str)),
          version: Dependabot::Version.new(T.must(detected_ver_str)),
          supported_versions: [
            Dependabot::Version.new(MINIMUM_VERSION),
            Dependabot::Version.new(CURRENT_VERSION)
          ],
          deprecated_versions: []
        )
      end

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def ecosystem
        {
          package_manager: "julia",
          version: version # This will use the potentially configured version
        }
      end
    end
  end
end
