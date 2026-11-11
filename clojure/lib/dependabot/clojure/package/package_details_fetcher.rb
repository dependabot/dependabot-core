# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/maven/shared/shared_package_details_fetcher"
require "dependabot/maven/shared/pom_release_date_fetcher"
require "dependabot/clojure/constants"
require "dependabot/clojure/native_helpers"

module Dependabot
  module Clojure
    module Package
      class PackageDetailsFetcher < Dependabot::Maven::Shared::SharedPackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials

          @repositories = T.let(nil, T.nilable(T::Array[RepositoryDetails]))
          @fetch = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
        end

        sig { override.returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { override.returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          @fetch ||= Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: versions.map do |version_details|
              Dependabot::Package::PackageRelease.new(
                version: version_details.fetch(:version),
                released_at: version_details.fetch(:release_date, nil),
                url: version_details.fetch(:source_url)
              )
            end
          )
        end

        # Clojars' directory listings have no dates, so cooldown reads the release
        # date from the POM's Last-Modified header.
        sig { params(release: Dependabot::Package::PackageRelease).returns(Dependabot::Package::PackageRelease) }
        def fetch_release_metadata(release:)
          @pom_release_date_fetcher ||= T.let(
            Maven::Shared::PomReleaseDateFetcher.new(self),
            T.nilable(Maven::Shared::PomReleaseDateFetcher)
          )
          @pom_release_date_fetcher.fetch_release_metadata(release: release)
        end

        # Registries from dependabot.yml come first, then the repositories declared
        # in project.clj or deps.edn, then Maven Central and Clojars.
        sig { override.returns(T::Array[RepositoryDetails]) }
        def repositories
          @repositories ||= (credentials_repository_details + repository_urls.map do |url|
            { URL_KEY => url, AUTH_HEADERS_KEY => auth_headers(url) }
          end).uniq { |details| details[URL_KEY] }
        end

        # A registry with replaces-base stands in for both Maven Central and Clojars.
        sig { override.returns(String) }
        def central_repo_url
          base_registry_url || CENTRAL_REPO_URL
        end

        private

        sig { returns(T::Array[String]) }
        def repository_urls
          declared = dependency_files.flat_map { |file| NativeHelpers.parse(file).repositories }
          defaults = base_registry_url ? [] : [CENTRAL_REPO_URL, CLOJARS_REPO_URL]

          (declared + defaults).map { |url| strip_trailing_slashes(url.strip) }
        end

        sig { returns(T.nilable(String)) }
        def base_registry_url
          credential = credentials.find do |cred|
            cred["type"] == REPOSITORY_TYPE && cred.replaces_base? && cred[URL_KEY]
          end
          credential && strip_trailing_slashes(T.must(credential[URL_KEY]))
        end
      end
    end
  end
end
