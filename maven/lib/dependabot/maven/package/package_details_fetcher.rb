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
require "dependabot/maven/shared/shared_maven_repository_client"
require "sorbet-runtime"

module Dependabot
  module Maven
    module Package
      class PackageDetailsFetcher < Dependabot::Maven::Shared::SharedMavenRepositoryClient
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = T.let(dependency, Dependabot::Dependency)
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])

          @pom_repository_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @repository_finder = T.let(nil, T.nilable(Maven::FileParser::RepositoriesFinder))
          @repositories_cache = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @version_details = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
          @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
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

        sig { returns(T::Array[T.untyped]) }
        def releases
          fetch.releases
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def released?(version)
          super
        end

        # Assembles the list of Maven repositories to search: credential repos + POM repos.
        sig { override.returns(T::Array[T::Hash[String, T.untyped]]) }
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

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def versions
          return @version_details if @version_details

          @version_details = versions_details_from_xml

          begin
            versions_details_hash = versions_details_hash_from_html if @version_details.any?

            if versions_details_hash
              @version_details = @version_details.map do |version_details|
                version = version_details[:version].to_s
                version_details_hash = versions_details_hash[version]

                next version_details unless version_details_hash

                release_date = version_details_hash[:release_date]

                next version_details unless release_date

                version_details.merge(
                  release_date: version_details_hash[:release_date],
                  source_url: version_details[:source_url]
                )
              end
            end
          rescue StandardError => e
            Dependabot.logger.error("Error fetching version details from HTML: #{e.message}")
          end

          @version_details = @version_details.sort_by { |details| details.fetch(:version) }
          @version_details
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def versions_details_from_xml
          forbidden_urls.clear
          version_details = repositories.flat_map do |repository_details|
            url = repository_details.fetch(URL_KEY)
            xml = dependency_metadata(repository_details)
            next [] if xml.nil?

            extract_metadata_from_xml(xml, url)
          end

          raise PrivateSourceAuthenticationFailure, forbidden_urls.first if version_details.none? && forbidden_urls.any?

          version_details
        end

        sig { returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
        def versions_details_hash_from_html
          forbidden_urls.clear

          # Iterate over repositories and fetch the first valid result
          versions_detail_hash = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
          repositories.each do |repository_details|
            html = dependency_metadata_from_html(repository_details)

            # Skip if no HTML data is found
            next if html.nil?

            # Break and return result from the first valid HTML
            versions_detail_hash = extract_version_details_from_html(html)

            break if versions_detail_hash.any?
          end

          # If no version details were found, but there are forbidden URLs, raise an error
          if versions_detail_hash.any? && forbidden_urls.any?
            raise PrivateSourceAuthenticationFailure,
                  forbidden_urls.first
          end

          # Return the populated version details hash (may be empty if no valid repositories)
          versions_detail_hash
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
        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
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
          filename = dependency.requirements.first&.fetch(:file) ||
                     dependency.requirements.first&.dig(:metadata, :pom_file)
          dependency_files.find { |f| f.name == filename }
        end
      end
    end
  end
end
