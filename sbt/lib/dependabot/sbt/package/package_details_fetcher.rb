# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/sbt/file_parser/repositories_finder"
require "dependabot/sbt/version"
require "dependabot/sbt/requirement"
require "dependabot/maven/shared/shared_package_details_fetcher"
require "dependabot/maven/utils/auth_headers_finder"

module Dependabot
  module Sbt
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
          @dependency = T.let(dependency, Dependabot::Dependency)
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])

          @repositories_cache = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @repository_finder = T.let(nil, T.nilable(Sbt::FileParser::RepositoriesFinder))
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

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def releases
          fetch.releases
        end

        # Assembles the list of Maven repositories to search: credential repos + SBT resolver repos.
        sig { override.returns(T::Array[T::Hash[String, T.untyped]]) }
        def repositories
          return @repositories_cache if @repositories_cache

          @repositories_cache = credentials_repository_details

          sbt_repository_details.each do |repo|
            @repositories_cache << repo unless @repositories_cache.any? do |r|
              r[URL_KEY] == repo[URL_KEY]
            end
          end

          @repositories_cache
        end

        sig { override.returns(String) }
        def central_repo_url
          Sbt::FileParser::RepositoriesFinder::CENTRAL_REPO_URL
        end

        private

        sig { returns(Sbt::FileParser::RepositoriesFinder) }
        def repository_finder
          @repository_finder ||= Sbt::FileParser::RepositoriesFinder.new(
            dependency_files: dependency_files,
            credentials: credentials
          )
        end

        # Returns the repository details discovered from SBT build files.
        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def sbt_repository_details
          repository_finder
            .repository_urls
            .map do |url|
              { URL_KEY => url, AUTH_HEADERS_KEY => auth_headers(url) }
            end
        end
      end
    end
  end
end
