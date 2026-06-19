# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_updater"
require "dependabot/gradle/file_updater/wrapper/gradle_version_capabilities"
require "dependabot/gradle/file_updater/wrapper/properties_document"

module Dependabot
  module Gradle
    class FileUpdater
      module Wrapper
        # Builds the argument list for Gradle's `wrapper` task.
        #
        # The output file is reconciled afterwards (see PropertiesReconciler), so these arguments do
        # not need to fully reproduce the user's file. We still forward the user's gated, run-relevant
        # settings (networkTimeout/retries/retryBackOffMs) when the *executing* Gradle version supports
        # them, both to honor the user's configuration during the run and to align with the wrapper
        # task's intended usage. Options unsupported by the executing version are omitted so the run
        # never aborts on an unknown flag.
        class CommandBuilder
          extend T::Sig

          # Maps an existing properties key to its wrapper CLI option and the capability key used to
          # decide whether the executing Gradle version understands the flag.
          STEERED_OPTIONS = T.let(
            [
              ["networkTimeout", "--network-timeout", GradleVersionCapabilities::NETWORK_TIMEOUT],
              ["retries", "--retries", GradleVersionCapabilities::RETRIES],
              ["retryBackOffMs", "--retry-back-off-ms", GradleVersionCapabilities::RETRY_BACK_OFF_MS]
            ].freeze,
            T::Array[[String, String, String]]
          )

          sig do
            params(
              requirements: T::Array[Dependabot::DependencyRequirement],
              original_properties: T.nilable(PropertiesDocument),
              gradle_version: T.nilable(Dependabot::Gradle::Version)
            ).void
          end
          def initialize(requirements:, original_properties:, gradle_version:)
            @requirements = requirements
            @original_properties = original_properties
            @gradle_version = gradle_version
          end

          sig { returns(T::Array[String]) }
          def build
            args = %W(wrapper --gradle-version #{version})

            # Dependabot's proxy cannot satisfy the HEAD request Gradle issues to validate the
            # distribution URL, so we always skip validation. The user's original
            # `validateDistributionUrl` value is preserved by reconciliation.
            args += %w(--no-validate-url)

            args += steered_args
            args += %W(--distribution-type #{distribution_type}) if distribution_type
            args += %W(--gradle-distribution-sha256-sum #{checksum}) if checksum
            args
          end

          private

          sig { returns(T::Array[String]) }
          def steered_args
            properties = @original_properties
            return [] if properties.nil?

            STEERED_OPTIONS.flat_map do |property_key, flag, capability|
              value = properties.value_for(property_key)
              next [] if value.nil? || value.strip.empty?
              next [] unless GradleVersionCapabilities.supports?(capability, @gradle_version)

              [flag, value]
            end
          end

          sig { returns(String) }
          def version
            T.let(T.must(@requirements[0])[:requirement], String)
          end

          sig { returns(T.nilable(String)) }
          def checksum
            return nil unless @requirements.size > 1

            T.let(T.must(@requirements[1])[:requirement], String)
          end

          sig { returns(T.nilable(String)) }
          def distribution_type
            url = T.let(T.must(@requirements[0])[:source], T::Hash[Symbol, String])[:url]
            # Anchor to the `-bin.zip` / `-all.zip` filename suffix so a path segment such as a
            # mirror host (e.g. https://binaries.example.com/...) can't false-match `bin`/`all`.
            url&.match(/-(bin|all)\.zip/)&.captures&.first
          end
        end
      end
    end
  end
end
