# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/package/package_details"
require "dependabot/package/package_latest_version_finder"
require "dependabot/registry_client"
require "dependabot/update_checkers/base"

require "dependabot/dotnet_sdk/package/package_details_fetcher"
require "dependabot/dotnet_sdk/requirement"
require "dependabot/dotnet_sdk/version"

module Dependabot
  module DotnetSdk
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          override.returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def package_details
          @package_details ||= Package::PackageDetailsFetcher.new(dependency: dependency).fetch
        end

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def latest_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          @latest_version ||= fetch_latest_version
        end

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def lowest_security_fix_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version
        end

        protected

        sig { override.returns(T::Boolean) }
        def wants_prerelease?
          !!dependency.metadata[:allow_prerelease]
        end

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_lowest_security_fix_versions_filter(releases)
          filter_prerelease_versions(releases)
        end
      end
    end
  end
end
