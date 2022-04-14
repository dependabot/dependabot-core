# frozen_string_literal: true

require "nokogiri"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Nuget
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        return Source.from_url(dependency_source_url) if dependency_source_url

        src_repo = look_up_source_in_nuspec(dependency_nuspec_file)
        return src_repo if src_repo

        src_repo_from_project
      end

      def src_repo_from_project
        source = dependency.requirements.find { |r| r&.fetch(:source) }&.fetch(:source)
        return unless source

        response = Excon.get(
          source.fetch(:url), # e.g. https://nuget.pkg.github.com/ORG/index.json
          idempotent: true,
          **SharedHelpers.excon_defaults(headers: auth_header)
        )
        return unless response.status == 200

        # Extract the query url e.g. https://nuget.pkg.github.com/ORG/query
        search_base = JSON.parse(response.body).
          fetch("resources", []).
          find { |r| r.fetch("@type") == "SearchQueryService" }&.
          fetch("@id")
        return unless search_base

        # Query for the package
        response = Excon.get(
          search_base + "?q=#{dependency.name.downcase}&prerelease=true&semVerLevel=2.0.0",
          idempotent: true,
          **SharedHelpers.excon_defaults(headers: auth_header)
        )
        return unless response.status == 200

        # Find a projectUrl or licenseUrl that look like a source URL
        JSON.parse(response.body).fetch("data", []).each do |searchResult|
          next unless searchResult["id"].downcase == dependency.name.downcase

          if searchResult.fetch("projectUrl")
            source = Source.from_url(searchResult.fetch("projectUrl"))
            return source unless source.repo.nil?
          end
          if searchResult.fetch("licenseUrl")
            source = Source.from_url(searchResult.fetch("licenseUrl"))
            return source unless source.repo.nil?
          end
        end
      end

      def look_up_source_in_nuspec(nuspec)
        potential_source_urls = [
          nuspec.at_css("package > metadata > repository")&.
            attribute("url")&.value,
          nuspec.at_css("package > metadata > repository > url")&.content,
          nuspec.at_css("package > metadata > projectUrl")&.content,
          nuspec.at_css("package > metadata > licenseUrl")&.content
        ].compact

        source_url = potential_source_urls.find { |url| Source.from_url(url) }
        source_url ||= source_from_anywhere_in_nuspec(nuspec)

        Source.from_url(source_url)
      end

      def source_from_anywhere_in_nuspec(nuspec)
        github_urls = []
        nuspec.to_s.force_encoding(Encoding::UTF_8).
          scan(Source::SOURCE_REGEX) do
          github_urls << Regexp.last_match.to_s
        end

        github_urls.find do |url|
          repo = Source.from_url(url).repo
          repo.downcase.end_with?(dependency.name.downcase)
        end
      end

      def dependency_nuspec_file
        return @dependency_nuspec_file unless @dependency_nuspec_file.nil?

        response = Excon.get(
          dependency_nuspec_url,
          idempotent: true,
          **SharedHelpers.excon_defaults(headers: auth_header)
        )

        @dependency_nuspec_file = Nokogiri::XML(response.body)
      end

      def dependency_nuspec_url
        puts "dependency.requirements #{dependency.requirements}"
        source = dependency.requirements.
                 find { |r| r&.fetch(:source) }&.fetch(:source)

        if source&.key?(:nuspec_url)
          source.fetch(:nuspec_url) ||
            "https://api.nuget.org/v3-flatcontainer/"\
            "#{dependency.name.downcase}/#{dependency.version}/"\
            "#{dependency.name.downcase}.nuspec"
        elsif source&.key?(:nuspec_url)
          source.fetch("nuspec_url") ||
            "https://api.nuget.org/v3-flatcontainer/"\
            "#{dependency.name.downcase}/#{dependency.version}/"\
            "#{dependency.name.downcase}.nuspec"
        else
          "https://api.nuget.org/v3-flatcontainer/"\
          "#{dependency.name.downcase}/#{dependency.version}/"\
          "#{dependency.name.downcase}.nuspec"
        end
      end

      def dependency_source_url
        source = dependency.requirements.
                 find { |r| r&.fetch(:source) }&.fetch(:source)

        return unless source
        return source.fetch(:source_url) if source.key?(:source_url)

        source.fetch("source_url")
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def auth_header
        source = dependency.requirements.
                 find { |r| r&.fetch(:source) }&.fetch(:source)
        url = source&.fetch(:url, nil) || source&.fetch("url")

        token = credentials.
                select { |cred| cred["type"] == "nuget_feed" }.
                find { |cred| cred["url"] == url }&.
                fetch("token", nil)

        return {} unless token

        if token.include?(":")
          encoded_token = Base64.encode64(token).delete("\n")
          { "Authorization" => "Basic #{encoded_token}" }
        elsif Base64.decode64(token).ascii_only? &&
              Base64.decode64(token).include?(":")
          { "Authorization" => "Basic #{token.delete("\n")}" }
        else
          { "Authorization" => "Bearer #{token}" }
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity
    end
  end
end

Dependabot::MetadataFinders.register("nuget", Dependabot::Nuget::MetadataFinder)
