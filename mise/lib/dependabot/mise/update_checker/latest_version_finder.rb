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

        sig { override.params(language_version: T.nilable(T.any(Dependabot::Version, String))).returns(T.nilable(Dependabot::Version)) }
        def latest_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          allowed_releases.max_by(&:version)&.version
        end

        sig { params(version: String).returns(T::Boolean) }
        def allowed?(version)
          allowed_releases.any? { |release| release.version.to_s == version }
        end

        # Asks mise, so tool options such as minimum_release_age apply.
        sig { params(pin: String).returns(T.nilable(String)) }
        def resolved_pin(pin)
          cache = @resolved_pins ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
          return cache[pin] if cache.key?(pin)

          cache[pin] = begin
            Dependabot::SharedHelpers.in_a_temporary_directory do
              write_manifest_files(dependency_files)
              Dependabot::SharedHelpers.run_shell_command(
                ["mise", "latest", "--", "#{dependency.name}@#{pin}"], stderr_to_stdout: false, env: mise_env
              ).strip
            end
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed
            nil
          end
        end

        private

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def allowed_releases
          @allowed_releases ||= T.let(
            filter_by_cooldown(filter_ignored_versions(filter_prerelease_versions(package_releases || []))),
            T.nilable(T::Array[Dependabot::Package::PackageRelease])
          )
        end

        # UpdateChecker scopes each finder to a single manifest.
        sig { returns(T::Hash[String, String]) }
        def mise_env
          {
            "MISE_YES" => "1",
            "MISE_SAFE" => "1",
            "MISE_OVERRIDE_CONFIG_FILENAMES" => T.must(dependency_files.first).name
          }
        end

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
              ["mise", "ls-remote", "--json", "--", dependency.name],
              stderr_to_stdout: false,
              env: mise_env
            )

            JSON.parse(raw).filter_map do |entry|
              version = entry["version"]
              next unless Dependabot::Mise::Version.correct?(version)

              released_at = entry["created_at"] ? Time.parse(entry["created_at"]) : nil

              Dependabot::Package::PackageRelease.new(
                version: Dependabot::Mise::Version.new(version),
                released_at: released_at
              )
            end
          end
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed, JSON::ParserError
          nil
        end
      end
    end
  end
end
