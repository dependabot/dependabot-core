# typed: strong
# frozen_string_literal: true

require "uri"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/powershell/package/package_details_fetcher"

module Dependabot
  module Powershell
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      PUBLIC_SOURCE_HOSTS = %w(github.com gitlab.com bitbucket.org dev.azure.com).freeze
      INVALID_PATH_SEGMENTS = %w(. ..).freeze
      GITHUB_REPOSITORY_PATH = %r{
        \A/(?<owner>[\w.-]+)/(?<repository>[\w.-]+)(?:/(?:tree|blob)/[^/]+(?:/.*)?)?/?\z
      }x
      GITLAB_REPOSITORY_PATH = %r{
        \A
        /(?<namespace>[\w.-]+(?:/[\w.-]+)?)
        /(?<repository>[\w.-]+)
        (?:(?:/-)?/(?:tree|blob)/[^/]+(?:/.*)?)?
        /?\z
      }x
      BITBUCKET_REPOSITORY_PATH = %r{
        \A/(?<owner>[\w.-]+)/(?<repository>[\w.-]+)(?:/src/[^/]+(?:/.*)?)?/?\z
      }x
      AZURE_REPOSITORY_PATH = %r{
        \A/(?<organization>[\w.-]+)(?:/(?<project>[\w.-]+))?/_git/(?<repository>[\w.-]+)/?\z
      }x

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        version = dependency.version
        return unless version

        project_url = package_details_fetcher.project_url_for(version)
        return unless project_url

        project_url = project_url.strip
        return if project_url.empty?

        source_url = canonical_source_url(project_url)
        Dependabot::Source.from_url(source_url) if source_url
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def canonical_source_url(url)
        uri = public_source_uri(url)
        return unless uri

        host = T.cast(uri.host, String).downcase
        path = T.cast(uri.path, String)
        return canonical_azure_url(host, path) if host == "dev.azure.com"
        return canonical_gitlab_url(host, path) if host == "gitlab.com"

        path_pattern = host == "bitbucket.org" ? BITBUCKET_REPOSITORY_PATH : GITHUB_REPOSITORY_PATH
        match = path_pattern.match(path)
        return unless match

        "https://#{host}/#{match[:owner]}/#{match[:repository]}"
      end

      sig { params(url: String).returns(T.nilable(URI::HTTP)) }
      def public_source_uri(url)
        uri = URI.parse(url)
        return unless uri.is_a?(URI::HTTP)

        host = uri.host&.downcase
        return unless host && PUBLIC_SOURCE_HOSTS.include?(host)
        return unless uri.userinfo.nil?
        return unless url.match?(%r{\Ahttps?://#{Regexp.escape(host)}/}i)
        return if T.cast(uri.path, String).split("/").intersect?(INVALID_PATH_SEGMENTS)

        uri
      rescue URI::Error
        nil
      end

      sig { params(host: String, path: String).returns(T.nilable(String)) }
      def canonical_gitlab_url(host, path)
        match = GITLAB_REPOSITORY_PATH.match(path)
        return unless match

        "https://#{host}/#{match[:namespace]}/#{match[:repository]}"
      end

      sig { params(host: String, path: String).returns(T.nilable(String)) }
      def canonical_azure_url(host, path)
        match = AZURE_REPOSITORY_PATH.match(path)
        return unless match

        project_path = match[:project] ? "/#{match[:project]}" : ""
        "https://#{host}/#{match[:organization]}#{project_path}/_git/#{match[:repository]}"
      end

      sig { returns(Dependabot::Powershell::Package::PackageDetailsFetcher) }
      def package_details_fetcher
        @package_details_fetcher ||= T.let(
          Dependabot::Powershell::Package::PackageDetailsFetcher.new(dependency: dependency),
          T.nilable(Dependabot::Powershell::Package::PackageDetailsFetcher)
        )
      end
    end
  end
end

Dependabot::MetadataFinders.register("powershell", Dependabot::Powershell::MetadataFinder)
