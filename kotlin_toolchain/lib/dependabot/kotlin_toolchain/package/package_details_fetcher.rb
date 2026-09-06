# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/gradle/package/package_details_fetcher"
require "dependabot/gradle/package/version_release_date_fallback_fetcher"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/file_parser/repositories_finder"
require "dependabot/kotlin_toolchain/wrapper"
require "dependabot/package/package_release"

module Dependabot
  module KotlinToolchain
    module Package
      class PackageDetailsFetcher < Dependabot::Gradle::Package::PackageDetailsFetcher
        extend T::Sig

        sig { override.returns(T::Array[T::Hash[String, Object]]) }
        def dependency_repository_details
          source_urls = dependency.requirements.filter_map do |requirement|
            source = requirement[:source]
            next unless source.is_a?(Hash)

            url = source[:url] || source["url"]
            url if url.is_a?(String)
          end

          urls = FileParser::RepositoriesFinder.new(
            dependency_files: dependency_files,
            credentials: credentials
          ).repository_urls + source_urls

          urls.uniq.map do |url|
            {
              "url" => url.sub(%r{/+$}, ""),
              "auth_headers" => auth_headers(url.sub(%r{/+$}, ""))
            }
          end
        end

        sig { override.returns(T::Array[String]) }
        def group_and_artifact_ids
          name = dependency.metadata[:maven_name]
          name = dependency.name unless name.is_a?(String)
          name.split(":", 2)
        end

        # Google Maven is a default repository for every Kotlin Toolchain
        # project, so it must not take the whole update down when unreachable.
        sig { override.returns(T.nilable(T::Array[T::Hash[Symbol, Object]])) }
        def google_version_details
          super
        rescue Excon::Error::Socket, Excon::Error::Timeout, Excon::Error::TooManyRedirects
          nil
        end

        # The JetBrains repository lists wrapper versions without dates, which
        # under cooldown would hide every release. The artifact's Last-Modified
        # header is the only release date it publishes.
        sig do
          override
            .params(release: Dependabot::Package::PackageRelease)
            .returns(Dependabot::Package::PackageRelease)
        end
        def fetch_release_metadata(release:)
          hydrated = super
          return hydrated if hydrated.released_at || !wrapper?

          build_release_with_date(hydrated, version_release_date_fallback(release.version.to_s))
        end

        sig { override.returns(Dependabot::Gradle::Package::VersionReleaseDateFallbackFetcher) }
        def version_release_date_fallback_fetcher
          return super unless wrapper?

          @version_release_date_fallback_fetcher ||= Dependabot::Gradle::Package::VersionReleaseDateFallbackFetcher.new(
            dependency_name: dependency.name,
            repositories: wrapper_repositories,
            forbidden_urls: forbidden_urls || [],
            pom_url_builder: lambda do |repository_url, version|
              Wrapper.artifact_url(repository: repository_url, version: version, windows: false)
            end
          )
        end

        sig { override.returns(T::Boolean) }
        def plugin?
          false
        end

        sig { override.returns(T::Boolean) }
        def kotlin_plugin?
          false
        end

        private

        sig { returns(T::Boolean) }
        def wrapper?
          dependency.name == WRAPPER_DEPENDENCY_NAME || dependency.metadata[:wrapper] == true
        end

        sig { returns(T::Array[T::Hash[String, Object]]) }
        def wrapper_repositories
          distribution_urls = dependency.requirements.filter_map do |requirement|
            source = requirement[:source]
            next unless source.is_a?(Hash)

            url = source[:url] || source["url"]
            url.sub(%r{/+$}, "") if url.is_a?(String)
          end

          own = repositories.select { |repository| distribution_urls.include?(repository["url"]) }
          own.empty? ? repositories : own
        end
      end
    end
  end
end
