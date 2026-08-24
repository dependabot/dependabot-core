# typed: strict
# frozen_string_literal: true

require "time"
require "excon"
require "nokogiri"
require "dependabot/registry_client"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/maven/file_parser/repositories_finder"
require "dependabot/maven/version"
require "dependabot/maven/requirement"
require "dependabot/maven/shared/shared_package_details_fetcher"
require "sorbet-runtime"

module Dependabot
  module Maven
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

          @pom_repository_details = T.let(nil, T.nilable(T::Array[RepositoryDetails]))
          @repository_finder = T.let(nil, T.nilable(Maven::FileParser::RepositoriesFinder))
          @repositories_cache = T.let(nil, T.nilable(T::Array[RepositoryDetails]))
          @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
          @release_date_cache = T.let({}, T::Hash[String, T.nilable(Time)])
          @fallback_logged = T.let(false, T::Boolean)
        end

        sig { override.returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { override.returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          return @package_details if @package_details

          releases = versions.map do |version_details|
            Dependabot::Package::PackageRelease.new(
              version: version_details.fetch(:version),
              released_at: version_details.fetch(:release_date, nil),
              url: version_details.fetch(:source_url)
            )
          end

          @package_details = Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: releases
          )

          @package_details
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def releases
          fetch.releases
        end

        sig { params(release: Dependabot::Package::PackageRelease).returns(Dependabot::Package::PackageRelease) }
        def fetch_release_metadata(release:)
          return release if release.released_at

          url = release.url
          return release unless url

          cache_key = "#{url}\0#{release.version}"
          released_at = if @release_date_cache.key?(cache_key)
                          @release_date_cache[cache_key]
                        else
                          @release_date_cache[cache_key] =
                            fetch_pom_last_modified(repository_url: url, version: release.version)
                        end
          return release unless released_at

          build_release_with_date(release, released_at)
        end

        # Assembles the list of Maven repositories to search: credential repos + POM repos.
        sig { override.returns(T::Array[RepositoryDetails]) }
        def repositories
          return @repositories_cache if @repositories_cache

          @repositories_cache = credentials_repository_details
          pom_repository_details.each do |repo|
            @repositories_cache << repo unless @repositories_cache.any? do |r|
              r[URL_KEY] == repo[URL_KEY]
            end
          end
          @repositories_cache
        end

        # Uses the Maven RepositoriesFinder's central URL to support credential-based overrides.
        sig { override.returns(String) }
        def central_repo_url
          repository_finder.central_repo_url
        end

        private

        sig do
          params(
            repository_url: String,
            version: Dependabot::Version
          ).returns(T.nilable(Time))
        end
        def fetch_pom_last_modified(repository_url:, version:)
          # release.url is the exact repository URL recorded when the version was
          # discovered, so an exact match is sufficient (no trailing-slash cleanup).
          repository_details = repositories.find do |details|
            self.repository_url(details) == repository_url
          end

          unless repository_details
            Dependabot.logger.debug(
              "No configured repository matches #{repository_url} for #{dependency.name}; " \
              "skipping POM Last-Modified fallback"
            )
            return
          end

          response = Dependabot::RegistryClient.head(
            url: dependency_pom_url(repository_url, version),
            headers: repository_auth_headers(repository_details)
          )
          return unless response.status < 400

          last_modified = response.headers["Last-Modified"] || response.headers["last-modified"]
          return unless last_modified

          released_at = Time.httpdate(last_modified)
          log_fallback_hit(repository_url: repository_url)
          Dependabot.logger.debug(
            "Using POM Last-Modified fallback for #{dependency.name} version #{version} from " \
            "#{repository_url}: #{released_at}"
          )
          released_at
        rescue StandardError => e
          Dependabot.logger.debug(
            "Failed POM Last-Modified fallback for #{dependency.name} version #{version} from " \
            "#{repository_url}: #{e.message}"
          )
          nil
        end

        sig { params(repository_url: String).void }
        def log_fallback_hit(repository_url:)
          return if @fallback_logged

          Dependabot.logger.info(
            "Using POM Last-Modified fallback release dates for #{dependency.name} from #{repository_url}"
          )
          @fallback_logged = true
        end

        sig do
          params(
            release: Dependabot::Package::PackageRelease,
            released_at: Time
          ).returns(Dependabot::Package::PackageRelease)
        end
        def build_release_with_date(release, released_at)
          Dependabot::Package::PackageRelease.new(
            version: release.version,
            released_at: released_at,
            latest: release.latest,
            yanked: release.yanked,
            yanked_reason: release.yanked_reason,
            downloads: release.downloads,
            url: release.url,
            package_type: release.package_type,
            language: release.language,
            tag: release.tag,
            details: release.details
          )
        end

        sig { returns(Maven::FileParser::RepositoriesFinder) }
        def repository_finder
          return @repository_finder if @repository_finder

          @repository_finder =
            Maven::FileParser::RepositoriesFinder.new(
              pom_fetcher: Maven::FileParser::PomFetcher.new(dependency_files: dependency_files),
              dependency_files: dependency_files,
              credentials: credentials
            )
          @repository_finder
        end

        # Returns the repository details for the POM file.
        sig { returns(T::Array[RepositoryDetails]) }
        def pom_repository_details
          return @pom_repository_details if @pom_repository_details

          @pom_repository_details =
            repository_finder
            .repository_urls(pom: T.must(pom))
            .map do |url|
              { URL_KEY => url, AUTH_HEADERS_KEY => {} }
            end
          @pom_repository_details
        end

        # Returns the POM file for the dependency, if it exists.
        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pom
          requirement = dependency.requirements.first
          filename = requirement&.file || requirement&.metadata_string("pom_file")
          dependency_files.find { |f| f.name == filename }
        end
      end
    end
  end
end
