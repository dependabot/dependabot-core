# typed: strong
# frozen_string_literal: true

require "dependabot/package/package_latest_version_finder"
require "dependabot/package/release_cooldown_options"
require "dependabot/update_checkers/version_filters"
require "dependabot/maven/package/package_details_fetcher"
require "dependabot/maven/update_checker"
require "dependabot/maven/shared/base_version_finder"
require "sorbet-runtime"

module Dependabot
  module Maven
    class UpdateChecker
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
          @forbidden_urls      = T.let([], T::Array[String])
          @dependency_metadata = T.let({}, T::Hash[T.untyped, Nokogiri::XML::Document])
          @auth_headers_finder = T.let(nil, T.nilable(Utils::AuthHeadersFinder))
          @pom_repository_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @repository_finder = T.let(nil, T.nilable(Maven::FileParser::RepositoriesFinder))
          @repositories = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @released_check = T.let({}, T::Hash[Version, T::Boolean])
          @package_details_fetcher = T.let(nil, T.nilable(Package::PackageDetailsFetcher))
          @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
          super
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
