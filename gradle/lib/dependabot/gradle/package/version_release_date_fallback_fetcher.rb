# typed: strict
# frozen_string_literal: true

require "dependabot/logger"
require "sorbet-runtime"
require "time"

module Dependabot
  module Gradle
    module Package
      class VersionReleaseDateFallbackFetcher
        extend T::Sig

        sig do
          params(
            dependency_name: String,
            repositories: T::Array[T::Hash[String, T.untyped]],
            forbidden_urls: T::Array[String],
            pom_url_builder: T.proc.params(repository_url: String, version: String).returns(String)
          ).void
        end
        def initialize(dependency_name:, repositories:, forbidden_urls:, pom_url_builder:)
          @dependency_name = dependency_name
          @repositories = repositories
          @forbidden_urls = forbidden_urls
          @pom_url_builder = pom_url_builder
          @cache = T.let({}, T::Hash[String, T.nilable(Time)])
          @preferred_repository_url = T.let(nil, T.nilable(String))
          @fallback_logged = T.let(false, T::Boolean)
        end

        sig { params(version: String).returns(T.nilable(Time)) }
        def fetch(version)
          return @cache[version] if @cache.key?(version)

          ordered_repositories.each do |repo|
            repository_url = repo.fetch("url")
            pom_url = @pom_url_builder.call(repository_url, version)

            begin
              response = Dependabot::RegistryClient.head(url: pom_url, headers: repo["auth_headers"])
              last_modified = response.headers["Last-Modified"] || response.headers["last-modified"]
              next unless last_modified

              released_at = Time.httpdate(last_modified)
              @preferred_repository_url = repository_url
              log_fallback_hit(version: version, repository_url: repository_url, released_at: released_at)
              @cache[version] = released_at
              return released_at
            rescue StandardError => e
              Dependabot.logger.debug(
                "Failed POM Last-Modified fallback for #{@dependency_name} version #{version} from " \
                "#{repository_url}: #{e.message}"
              )
            end
          end

          Dependabot.logger.debug(
            "No POM Last-Modified fallback release date found for #{@dependency_name} version #{version}"
          )
          @cache[version] = nil
        end

        private

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def ordered_repositories
          candidates = @repositories.reject do |repo|
            @forbidden_urls.include?(repo.fetch("url"))
          end

          preferred, remaining = candidates.partition do |repo|
            @preferred_repository_url && repo.fetch("url") == @preferred_repository_url
          end

          preferred + remaining
        end

        sig { params(version: String, repository_url: String, released_at: Time).void }
        def log_fallback_hit(version:, repository_url:, released_at:)
          Dependabot.logger.debug(
            "Using POM Last-Modified fallback for #{@dependency_name} version #{version} from " \
            "#{repository_url}: #{released_at}"
          )
          return if @fallback_logged

          Dependabot.logger.info(
            "Using POM Last-Modified fallback release dates for #{@dependency_name} from #{repository_url}"
          )
          @fallback_logged = true
        end
      end
    end
  end
end
