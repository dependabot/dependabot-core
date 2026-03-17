# typed: strict
# frozen_string_literal: true

require "dependabot/package/package_latest_version_finder"
require "dependabot/mise/helpers"
require "dependabot/mise/requirement"
require "dependabot/mise/version"
require "dependabot/shared_helpers"
require "json"

module Dependabot
  module Mise
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig
        include Dependabot::Mise::Helpers

        # Not used — we bypass the parent's package_details/available_versions flow.
        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end

        # We override latest_version rather than relying on the parent's fetch_latest_release
        # because the parent's filter_prerelease_versions would incorrectly discard mise version
        # strings like "1.18.4-otp-27": Gem::Version treats non-numeric segments as pre-release.
        sig { override.params(language_version: T.nilable(T.any(Dependabot::Version, String))).returns(T.nilable(Dependabot::Version)) }
        def latest_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          releases = package_releases
          return nil if releases.nil? || releases.empty?

          releases = filter_ignored_versions(releases)
          releases = filter_by_cooldown(releases)
          releases.max_by(&:version)&.version
        end

        private

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def package_releases
          @package_releases ||= T.let(
            fetch_releases,
            T.nilable(T::Array[Dependabot::Package::PackageRelease])
          )
        end

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def fetch_releases
          Dependabot::SharedHelpers.in_a_temporary_directory do
            write_manifest_files(dependency_files)

            raw = Dependabot::SharedHelpers.run_shell_command(
              "mise ls-remote --json #{dependency.name}",
              stderr_to_stdout: false,
              env: { "MISE_YES" => "1" }
            )

            JSON.parse(raw).filter_map do |entry|
              version = entry["version"]
              next unless version

              released_at = entry["created_at"] ? Time.parse(entry["created_at"]) : nil

              Dependabot::Package::PackageRelease.new(
                version: Dependabot::Mise::Version.new(version),
                released_at: released_at
              )
            end
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
