# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module Nuget
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      sig do
        override
          .params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          )
          .void
      end
      def initialize(dependency:, credentials:)
        @dependency_nuspec_file = T.let(nil, T.nilable(Nokogiri::XML::Document))

        super
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        return Source.from_url(dependency_source_url) if dependency_source_url

        if dependency_nuspec_file
          src_repo = look_up_source_in_nuspec(T.must(dependency_nuspec_file))
          return src_repo if src_repo
        end

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

      sig { returns(T.nilable(Dependabot::Source)) }
      def src_repo_from_project
        source = dependency.requirements.find { |r| r.fetch(:source) }&.fetch(:source)
        return unless source

        # Query the service index e.g. https://nuget.pkg.github.com/ORG/index.json
        response = Dependabot::RegistryClient.get(
          url: source.fetch(:url),
          headers: { **auth_header, "Accept" => "application/json" }
        )
        return unless response.status == 200

        # Extract the query url e.g. https://nuget.pkg.github.com/ORG/query
        search_base = extract_search_url(response.body)
        return unless search_base

        response = Dependabot::RegistryClient.get(
          url: search_base + "?q=#{dependency.name.downcase}&prerelease=true&semVerLevel=2.0.0",
          headers: { **auth_header, "Accept" => "application/json" }
        )
        return unless response.status == 200

        # Find a projectUrl or licenseUrl that look like a source URL
        extract_source_repo(response.body)
      rescue JSON::ParserError
        # Ignored, this is expected for some registries that don't handle these request.
      end

      sig { params(body: String).returns(T.nilable(String)) }
      def extract_search_url(body)
        JSON.parse(body)
            .fetch("resources", [])
            .find { |r| r.fetch("@type") == "SearchQueryService" }
            &.fetch("@id")
      end

      sig { params(body: String).returns(T.nilable(Dependabot::Source)) }
      def extract_source_repo(body)
        JSON.parse(body).fetch("data", []).each do |search_result|
          next unless search_result["id"].casecmp(dependency.name).zero?

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

      sig { params(nuspec: Nokogiri::XML::Document).returns(T.nilable(Dependabot::Source)) }
      def look_up_source_in_nuspec(nuspec)
        potential_source_urls = [
          nuspec.at_css("package > metadata > repository")
                &.attribute("url")&.value,
          nuspec.at_css("package > metadata > repository > url")&.content,
          nuspec.at_css("package > metadata > projectUrl")&.content,
          nuspec.at_css("package > metadata > licenseUrl")&.content
        ].compact

        source_url = potential_source_urls.find { |url| Source.from_url(url) }
        source_url ||= source_from_anywhere_in_nuspec(nuspec)

        Source.from_url(source_url)
      end

      sig { params(nuspec: Nokogiri::XML::Document).returns(T.nilable(String)) }
      def source_from_anywhere_in_nuspec(nuspec)
        github_urls = []
        nuspec.to_s.force_encoding(Encoding::UTF_8)
              .scan(Source::SOURCE_REGEX) do
          github_urls << Regexp.last_match.to_s
        end

        github_urls.find do |url|
          repo = T.must(Source.from_url(url)).repo
          repo.downcase.end_with?(dependency.name.downcase)
        end
      end

      sig { returns(T.nilable(Nokogiri::XML::Document)) }
      def dependency_nuspec_file
        return @dependency_nuspec_file unless @dependency_nuspec_file.nil?

        return if dependency_nuspec_url.nil?

        response = Dependabot::RegistryClient.get(
          url: T.must(dependency_nuspec_url),
          headers: auth_header
        )

        @dependency_nuspec_file = Nokogiri::XML(response.body)
      end

      sig { returns(T.nilable(String)) }
      def dependency_nuspec_url
        source = dependency.requirements
                           .find { |r| r.fetch(:source) }&.fetch(:source)

        source.fetch(:nuspec_url) if source&.key?(:nuspec_url)
      end

      sig { returns(T.nilable(String)) }
      def dependency_source_url
        source = dependency.requirements
                           .find { |r| r.fetch(:source) }&.fetch(:source)

        return unless source
        return source.fetch(:source_url) if source.key?(:source_url)

        source.fetch("source_url")
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(T::Hash[String, String]) }
      def auth_header
        source = dependency.requirements
                           .find { |r| r.fetch(:source) }&.fetch(:source)
        url = source&.fetch(:url, nil) || source&.fetch("url")

        token = credentials
                .select { |cred| cred["type"] == "nuget_feed" }
                .find { |cred| cred["url"] == url }
                &.fetch("token", nil)

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
