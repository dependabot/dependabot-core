# typed: true
# frozen_string_literal: true

require "nokogiri"
require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/nuget/nuget_client"
require "dependabot/registry_client"

module Dependabot
  module Nuget
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      def look_up_source
        return Source.from_url(dependency_source_url) if dependency_source_url

        source = dependency.requirements.find { |r| r&.fetch(:source) }&.fetch(:source)
        token = auth_token
        source[:token] = token if token
        repo_details = NugetClient.build_repository_details(source, dependency.name)
        return unless repo_details

        source_repo = src_repo_from_project(repo_details)

        # Fallback to getting source from the search result's projectUrl or licenseUrl.
        # GitHub Packages doesn't support getting the `.nuspec`, switch to getting
        # that instead once it is supported.
        source_repo
      rescue StandardError
        # At this point in the process the PR is ready to be posted, we tried to gather commit
        # and release notes, but have encountered an exception. So let's eat it since it's
        # better to have a PR with no info than error out.
        nil
      end

      def src_repo_from_project(repo_details)
        packages = NugetClient.get_packages(repo_details)

        return unless packages

        # Find a projectUrl or licenseUrl that look like a source URL
        source_repos = packages.select do |package|
          source_repo = extract_source_repo(package)
          return source_repo if source_repo
        end
        source_repos.first
      rescue JSON::ParserError
        # Ignored, this is expected for some registries that don't handle these request.
      end

      def extract_source_repo(package)
        if package["projectUrl"] && package["projectUrl"] != ""
          source = Source.from_url(package["projectUrl"])
          return source if source
        end
        return unless package["licenseUrl"] && package["licenseUrl"] != ""

        Source.from_url(package["licenseUrl"])
      end

      def dependency_source_url
        source = dependency.requirements
                           .find { |r| r.fetch(:source) }&.fetch(:source)

        return unless source
        return source.fetch(:source_url) if source.key?(:source_url)

        source.fetch("source_url", nil)
      end

      def auth_token
        source = dependency.requirements
                           .find { |r| r.fetch(:source) }&.fetch(:source)
        url = source&.fetch(:url, nil) || source&.fetch("url")

        token = credentials
                .select { |cred| cred["type"] == "nuget_feed" }
                .find { |cred| cred["url"] == url }
                &.fetch("token", nil)

        token
      end
    end
  end
end

Dependabot::MetadataFinders.register("nuget", Dependabot::Nuget::MetadataFinder)
