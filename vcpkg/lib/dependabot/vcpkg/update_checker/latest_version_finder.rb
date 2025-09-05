# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers/base"
require "dependabot/package/package_latest_version_finder"

require "dependabot/vcpkg/package/package_details_fetcher"
require "dependabot/vcpkg/requirement"
require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= T.let(
            Package::PackageDetailsFetcher.new(dependency: dependency).fetch,
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          latest_release_info&.version
        end

        sig { returns(T.nilable(Dependabot::Package::PackageRelease)) }
        def latest_release_info
          @latest_release_info ||= T.let(
            begin
              releases = available_versions
              return unless releases

              releases = filter_yanked_versions(releases)
              releases = filter_by_cooldown(releases)
              releases = filter_ignored_versions(releases)

              releases.max_by(&:version)
            end,
            T.nilable(Dependabot::Package::PackageRelease)
          )
        end

        private

        sig { returns(T::Boolean) }
        def registry_dependency?
          dependency.source_details(allowed_types: ["git"]) in { type: "git" }
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled? = true
      end
    end
  end
end
