# frozen_string_literal: true

require "nokogiri"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/file_fetchers/base"
require "dependabot/maven/file_parser"
require "dependabot/maven/file_parser/repositories_finder"

module Dependabot
  module Maven
    class MetadataFinder < Dependabot::MetadataFinders::Base
      DOT_SEPARATOR_REGEX = %r{\.(?!\d+([.\/_]|$)+)}.freeze

      private

      def look_up_source
        tmp_source = look_up_source_in_pom(dependency_pom_file)
        return tmp_source if tmp_source

        return unless (parent = parent_pom_file(dependency_pom_file))

        tmp_source = look_up_source_in_pom(parent)
        return unless tmp_source

        artifact = dependency.name.split(":").last
        return tmp_source if tmp_source.repo.end_with?(artifact)
        return tmp_source if repo_has_subdir_for_dep?(tmp_source)
      end

      def repo_has_subdir_for_dep?(tmp_source)
        @repo_has_subdir_for_dep ||= {}
        if @repo_has_subdir_for_dep.key?(tmp_source)
          return @repo_has_subdir_for_dep[tmp_source]
        end

        artifact = dependency.name.split(":").last
        fetcher =
          FileFetchers::Base.new(source: tmp_source, credentials: credentials)

        @repo_has_subdir_for_dep[tmp_source] =
          fetcher.send(:repo_contents, raise_errors: false).
          select { |f| f.type == "dir" }.
          any? { |f| artifact.end_with?(f.name) }
      rescue Dependabot::RepoNotFound
        @repo_has_subdir_for_dep[tmp_source] = false
      end

      def look_up_source_in_pom(pom)
        potential_source_urls = [
          pom.at_css("project > url")&.content,
          pom.at_css("project > scm > url")&.content,
          pom.at_css("project > issueManagement > url")&.content
        ].compact

        source_url = potential_source_urls.find { |url| Source.from_url(url) }
        source_url ||= source_from_anywhere_in_pom(pom)
        source_url = substitute_properties_in_source_url(source_url, pom)

        Source.from_url(source_url)
      end

      def substitute_properties_in_source_url(source_url, pom)
        return unless source_url
        return source_url unless source_url.include?("${")

        regex = Maven::FileParser::PROPERTY_REGEX
        property_name = source_url.match(regex).named_captures["property"]
        doc = pom.dup
        doc.remove_namespaces!
        nm = property_name.sub(/^pom\./, "").sub(/^project\./, "")
        property_value =
          loop do
            candidate_node =
              doc.at_xpath("/project/#{nm}") ||
              doc.at_xpath("/project/properties/#{nm}") ||
              doc.at_xpath("/project/profiles/profile/properties/#{nm}")
            break(candidate_node.content) if candidate_node
            break unless nm.match?(DOT_SEPARATOR_REGEX)

            nm = nm.sub(DOT_SEPARATOR_REGEX, "/")
          end

        url = source_url.gsub(source_url.match(regex).to_s, property_value.to_s)
        substitute_properties_in_source_url(url, pom)
      end

      def source_from_anywhere_in_pom(pom)
        github_urls = []
        pom.to_s.scan(Source::SOURCE_REGEX) do
          github_urls << Regexp.last_match.to_s
        end

        github_urls.find do |url|
          repo = Source.from_url(url).repo
          repo.end_with?(dependency.name.split(":").last)
        end
      end

      def dependency_pom_file
        return @dependency_pom_file unless @dependency_pom_file.nil?

        artifact_id = dependency.name.split(":").last
        response = Excon.get(
          "#{maven_repo_dependency_url}/"\
          "#{dependency.version}/"\
          "#{artifact_id}-#{dependency.version}.pom",
          headers: auth_details,
          idempotent: true,
          **SharedHelpers.excon_defaults
        )

        @dependency_pom_file = Nokogiri::XML(response.body)
      rescue Excon::Error::Timeout
        @dependency_pom_file = Nokogiri::XML("")
      end

      def parent_pom_file(pom)
        doc = pom.dup
        doc.remove_namespaces!
        group_id = doc.at_xpath("/project/parent/groupId")&.content&.strip
        artifact_id =
          doc.at_xpath("/project/parent/artifactId")&.content&.strip
        version = doc.at_xpath("/project/parent/version")&.content&.strip

        return unless artifact_id && group_id && version

        url = "#{maven_repo_url}/#{group_id.tr('.', '/')}/#{artifact_id}/"\
              "#{version}/"\
              "#{artifact_id}-#{version}.pom"

        response = Excon.get(
          substitute_properties_in_source_url(url, pom),
          headers: auth_details,
          idempotent: true,
          **SharedHelpers.excon_defaults
        )

        Nokogiri::XML(response.body)
      end

      def maven_repo_url
        source = dependency.requirements.
                 find { |r| r&.fetch(:source) }&.fetch(:source)

        source&.fetch(:url, nil) ||
          source&.fetch("url") ||
          Maven::FileParser::RepositoriesFinder::CENTRAL_REPO_URL
      end

      def maven_repo_dependency_url
        group_id, artifact_id = dependency.name.split(":")

        "#{maven_repo_url}/#{group_id.tr('.', '/')}/#{artifact_id}"
      end

      def auth_details
        cred =
          credentials.select { |c| c["type"] == "maven_repository" }.
          find do |c|
            cred_url = c.fetch("url").gsub(%r{/+$}, "")
            next false unless cred_url == maven_repo_url

            c.fetch("username", nil)
          end

        return {} unless cred

        token = cred.fetch("username") + ":" + cred.fetch("password")
        encoded_token = Base64.encode64(token).delete("\n")
        { "Authorization" => "Basic #{encoded_token}" }
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("maven", Dependabot::Maven::MetadataFinder)
