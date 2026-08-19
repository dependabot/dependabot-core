# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/package/package_latest_version_finder"
require "dependabot/package/release_cooldown_options"
require "dependabot/update_checkers/version_filters"
require "dependabot/maven/shared/base_version_finder"
require "dependabot/sbt/update_checker"
require "dependabot/sbt/package/package_details_fetcher"

module Dependabot
  module Sbt
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class VersionFinder < Dependabot::Maven::Shared::BaseVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          cooldown_options: nil,
          raise_on_ignored: false
        )
          @package_details_fetcher = T.let(nil, T.nilable(Package::PackageDetailsFetcher))
          @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))

          super(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            cooldown_options: cooldown_options,
            raise_on_ignored: raise_on_ignored,
            options: {}
          )
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= package_details_fetcher.fetch
        end

        private

        sig { override.params(version: Dependabot::Version).returns(T::Boolean) }
        def released?(version)
          package_details_fetcher.released?(version)
        end

        sig { returns(Package::PackageDetailsFetcher) }
        def package_details_fetcher
          @package_details_fetcher ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          )
        end
      end
    end
  end
end
