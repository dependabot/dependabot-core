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

        # Fallback to getting source from the search result's projectUrl or licenseUrl.
        # GitHub Packages doesn't support getting the `.nuspec`, switch to getting
        # that instead once it is supported.
        src_repo_from_project
      rescue StandardError
        # At this point in the process the PR is ready to be posted, we tried to gather commit
        # and release notes, but have encountered an exception. So let's eat it since it's
        # better to have a PR with no info than error out.
        nil
      end

      def src_repo_from_project
        source = dependency.requirements.find { |r| r&.fetch(:source) }&.fetch(:source)
        return unless source

        # Query the service index e.g. https://nuget.pkg.github.com/ORG/index.json
        response = Excon.get(
          source.fetch(:url),
          idempotent: true,
          **SharedHelpers.excon_defaults(headers: { **auth_header, "Accept" => "application/json" })
        )
        return unless response.status == 200

        # Extract the query url e.g. https://nuget.pkg.github.com/ORG/query
        search_base = extract_search_url(response.body)
        return unless search_base

        response = Excon.get(
          search_base + "?q=#{dependency.name.downcase}&prerelease=true&semVerLevel=2.0.0",
          idempotent: true,
          **SharedHelpers.excon_defaults(headers: { **auth_header, "Accept" => "application/json" })
        )
        return unless response.status == 200

        # Find a projectUrl or licenseUrl that look like a source URL
        extract_source_repo(response.body)
      rescue JSON::ParserError
        # Ignored, this is expected for some registries that don't handle these request.
      end

      def extract_search_url(body)
        JSON.parse(body).
          fetch("resources", []).
          find { |r| r.fetch("@type") == "SearchQueryService" }&.
          fetch("@id")
      end

      def extract_source_repo(body)
        JSON.parse(body).fetch("data", []).each do |search_result|
          next unless search_result["id"].downcase == dependency.name.downcase

          if search_result.key?("projectUrl")
            source = Source.from_url(search_result.fetch("projectUrl"))
            return source if source
          end
          if search_result.key?("licenseUrl")
            source = Source.from_url(search_result.fetch("licenseUrl"))
            return source if source
          end
        end
        # failed to find a source URL
        nil
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
