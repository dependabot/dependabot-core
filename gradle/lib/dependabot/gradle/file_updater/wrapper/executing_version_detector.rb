# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_updater"
require "dependabot/gradle/version"

module Dependabot
  module Gradle
    class FileUpdater
      module Wrapper
        # Detects the Gradle version that will actually *execute* the wrapper task.
        #
        # The wrapper task runs under whatever Gradle the project currently resolves to (the OLD
        # distribution), not the target version. Knowing that version lets CommandBuilder decide
        # which version-gated CLI flags are safe to pass.
        module ExecutingVersionDetector
          extend T::Sig

          # Matches the version embedded in a Gradle distribution URL, e.g.
          # https://services.gradle.org/distributions/gradle-9.5.0-bin.zip
          # Anchored to the `gradle-<version>-(bin|all).zip` filename so host/port numbers in custom
          # mirror URLs are never mistaken for the version. The captured token is validated with
          # Version.correct? so non-version matches (and RC/milestone names) are handled safely.
          DISTRIBUTION_URL_VERSION_REGEX = T.let(
            /gradle-(?<version>.+?)-(?:bin|all)\.zip/,
            Regexp
          )

          # Matches the version printed by `gradle --version`, e.g. "Gradle 9.2.1".
          GRADLE_VERSION_OUTPUT_REGEX = T.let(/^Gradle\s+(?<version>\d+(?:\.\d+){1,2}(?:-[\w.]+)?)/, Regexp)

          sig { params(distribution_url: T.nilable(String)).returns(T.nilable(Dependabot::Gradle::Version)) }
          def self.from_distribution_url(distribution_url)
            return nil if distribution_url.nil?

            captured = distribution_url.match(DISTRIBUTION_URL_VERSION_REGEX)&.named_captures&.fetch("version", nil)
            build_version(captured)
          end

          sig { params(output: T.nilable(String)).returns(T.nilable(Dependabot::Gradle::Version)) }
          def self.from_version_output(output)
            return nil if output.nil?

            captured = output.match(GRADLE_VERSION_OUTPUT_REGEX)&.named_captures&.fetch("version", nil)
            build_version(captured)
          end

          sig { params(captured: T.nilable(String)).returns(T.nilable(Dependabot::Gradle::Version)) }
          def self.build_version(captured)
            return nil if captured.nil? || !Dependabot::Gradle::Version.correct?(captured)

            T.cast(Dependabot::Gradle::Version.new(captured), Dependabot::Gradle::Version)
          end
        end
      end
    end
  end
end
