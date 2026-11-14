# typed: strong
# frozen_string_literal: true

require "time"
require "sorbet-runtime"
require "dependabot/logger"
require "dependabot/registry_client"
require "dependabot/package/package_release"
require "dependabot/maven/shared/shared_package_details_fetcher"

module Dependabot
  module Maven
    module Shared
      # Fills in a missing release date from the POM's Last-Modified header, for
      # repositories whose directory listings have no dates.
      class PomReleaseDateFetcher
        extend T::Sig

        sig { params(package_details_fetcher: SharedPackageDetailsFetcher).void }
        def initialize(package_details_fetcher)
          @package_details_fetcher = package_details_fetcher
          @release_date_cache = T.let({}, T::Hash[String, T.nilable(Time)])
          @fallback_logged = T.let(false, T::Boolean)
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

        private

        sig { returns(SharedPackageDetailsFetcher) }
        attr_reader :package_details_fetcher

        sig { returns(String) }
        def dependency_name
          package_details_fetcher.dependency.name
        end

        sig do
          params(
            repository_url: String,
            version: Dependabot::Version
          ).returns(T.nilable(Time))
        end
        def fetch_pom_last_modified(repository_url:, version:)
          # release.url is the exact repository URL recorded when the version was
          # discovered, so an exact match is sufficient (no trailing-slash cleanup).
          repository_details = package_details_fetcher.repositories.find do |details|
            package_details_fetcher.repository_url(details) == repository_url
          end

          unless repository_details
            Dependabot.logger.debug(
              "No configured repository matches #{repository_url} for #{dependency_name}; " \
              "skipping POM Last-Modified fallback"
            )
            return
          end

          response = Dependabot::RegistryClient.head(
            url: package_details_fetcher.dependency_pom_url(repository_url, version),
            headers: package_details_fetcher.repository_auth_headers(repository_details)
          )
          return unless response.status < 400

          last_modified = response.headers["Last-Modified"] || response.headers["last-modified"]
          return unless last_modified

          released_at = Time.httpdate(last_modified)
          log_fallback_hit(repository_url: repository_url)
          Dependabot.logger.debug(
            "Using POM Last-Modified fallback for #{dependency_name} version #{version} from " \
            "#{repository_url}: #{released_at}"
          )
          released_at
        rescue StandardError => e
          Dependabot.logger.debug(
            "Failed POM Last-Modified fallback for #{dependency_name} version #{version} from " \
            "#{repository_url}: #{e.message}"
          )
          nil
        end

        sig { params(repository_url: String).void }
        def log_fallback_hit(repository_url:)
          return if @fallback_logged

          Dependabot.logger.info(
            "Using POM Last-Modified fallback release dates for #{dependency_name} from #{repository_url}"
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
      end
    end
  end
end
