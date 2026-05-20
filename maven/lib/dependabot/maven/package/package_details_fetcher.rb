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
          @dependency = T.let(dependency, Dependabot::Dependency)
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])

          @pom_repository_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @repository_finder = T.let(nil, T.nilable(Maven::FileParser::RepositoriesFinder))
          @repositories_cache = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
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
