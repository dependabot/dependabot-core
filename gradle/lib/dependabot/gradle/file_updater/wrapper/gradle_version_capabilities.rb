# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_updater"
require "dependabot/gradle/version"

module Dependabot
  module Gradle
    class FileUpdater
      module Wrapper
        # Declarative table of `wrapper` task command-line options and the minimum Gradle
        # version that supports each one. The wrapper task is executed by the Gradle version
        # currently resolved by the project (not the target version), so passing an option
        # that the executing Gradle does not understand would abort the run. We use this table
        # to only emit options that are safe for the executing version.
        #
        # Sources (gradle/gradle `Wrapper.java`):
        #   --network-timeout       @since 7.6
        #   --validate-url          @since 8.2  (incubating)
        #   --retries               @since 9.5.0 (incubating)
        #   --retry-back-off-ms     @since 9.5.0 (incubating)
        module GradleVersionCapabilities
          extend T::Sig

          NETWORK_TIMEOUT = "network-timeout"
          VALIDATE_URL = "validate-url"
          RETRIES = "retries"
          RETRY_BACK_OFF_MS = "retry-back-off-ms"

          MINIMUM_VERSIONS = T.let(
            {
              NETWORK_TIMEOUT => "7.6",
              VALIDATE_URL => "8.2",
              RETRIES => "9.5.0",
              RETRY_BACK_OFF_MS => "9.5.0"
            }.freeze,
            T::Hash[String, String]
          )

          # Returns true when the given (executing) Gradle version is known to support the option.
          # When the version is unknown (nil) we conservatively refuse options that are gated behind
          # a minimum version, so we never pass a flag that could abort the wrapper run. Reconciliation
          # of the properties file guarantees the user's value is preserved regardless.
          sig { params(option: String, gradle_version: T.nilable(Dependabot::Gradle::Version)).returns(T::Boolean) }
          def self.supports?(option, gradle_version)
            minimum = MINIMUM_VERSIONS[option]
            return true if minimum.nil? # ungated option

            return false if gradle_version.nil?

            gradle_version >= Dependabot::Gradle::Version.new(minimum)
          end
        end
      end
    end
  end
end
