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

        # Override to always use "jar" for the HEAD check. The SBT parser sets
        # packaging_type to "cross-versioned" as metadata for %% dependencies, but the
        # actual Maven artifact is always a .jar file.
        sig { override.params(repository_url: String, version: Dependabot::Version).returns(String) }
        def dependency_files_url(repository_url, version)
          _, artifact_id = dependency_parts
          base_url = dependency_base_url(repository_url)

          "#{base_url}/#{version}/#{artifact_id}-#{version}.jar"
        end

        # Override to handle SBT plugin cross-versioning.
        # SBT plugins are published with a double-suffix: artifact_scalaVersion_sbtVersion
        # e.g., sbt-jmh_2.12_1.0 for SBT 1.x plugins.
        sig { override.returns([String, String]) }
        def dependency_parts
          @dependency_parts = T.let(@dependency_parts, T.nilable([String, String]))
          return @dependency_parts if @dependency_parts

          group_id, artifact_id = dependency.name.split(":")
          group_path = T.must(group_id).tr(".", "/")

          artifact_id = "#{artifact_id}_#{plugin_scala_version}_#{sbt_binary_version}" if sbt_plugin?

          @dependency_parts = [group_path, T.must(artifact_id)]
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

        # SBT plugins are identified by having "plugins" in their groups.
        sig { returns(T::Boolean) }
        def sbt_plugin?
          dependency.requirements.any? { |req| req.fetch(:groups, []).include?("plugins") }
        end

        # SBT 1.x plugins use Scala 2.12; SBT 2.x plugins use Scala 3.
        sig { returns(String) }
        def plugin_scala_version
          sbt_major_version >= 2 ? "3" : "2.12"
        end

        # SBT binary version for plugin cross-versioning: "1.0" for SBT 1.x, "2.0" for SBT 2.x.
        sig { returns(String) }
        def sbt_binary_version
          "#{sbt_major_version}.0"
        end

        sig { returns(Integer) }
        def sbt_major_version
          build_properties = dependency_files.find { |f| f.name.end_with?("build.properties") }
          return 1 unless build_properties&.content

          T.must(build_properties.content).each_line do |line|
            match = line.strip.match(Sbt::FileParser::SBT_VERSION_REGEX)
            next unless match

            return T.must(match[:version]).strip.split(".").first.to_i
          end

          1
        end
      end
    end
  end
end
