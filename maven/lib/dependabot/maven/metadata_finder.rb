# frozen_string_literal: true

require "nokogiri"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/file_fetchers/base"
require "dependabot/maven/file_parser"
require "dependabot/maven/file_parser/repositories_finder"
require "dependabot/maven/utils/auth_headers_finder"

module Dependabot
  module Maven
    class MetadataFinder < Dependabot::MetadataFinders::Base
      DOT_SEPARATOR_REGEX = %r{\.(?!\d+([.\/_\-]|$)+)}.freeze

      private

      def look_up_source
        tmp_source = look_up_source_in_pom(dependency_pom_file)
        return tmp_source if tmp_source

        return unless (parent = parent_pom_file(dependency_pom_file))

        tmp_source = look_up_source_in_pom(parent)
        return unless tmp_source

        return tmp_source if tmp_source.repo.end_with?(dependency_artifact_id)
        return tmp_source if repo_has_subdir_for_dep?(tmp_source)
      end

      def repo_has_subdir_for_dep?(tmp_source)
        @repo_has_subdir_for_dep ||= {}
        return @repo_has_subdir_for_dep[tmp_source] if @repo_has_subdir_for_dep.key?(tmp_source)

        fetcher =
          FileFetchers::Base.new(source: tmp_source, credentials: credentials)

        @repo_has_subdir_for_dep[tmp_source] =
          fetcher.send(:repo_contents, raise_errors: false).
          select { |f| f.type == "dir" }.
          any? { |f| dependency_artifact_id.end_with?(f.name) }
      rescue Dependabot::BranchNotFound
        # If we are attempting to find a branch, we should fail over to the default branch and retry once only
        if tmp_source.branch.present?
          tmp_source.branch = nil
          retry
        end
        @repo_has_subdir_for_dep[tmp_source] = false
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
          repo.end_with?(dependency_artifact_id)
        end
      end

      def dependency_pom_file
        return @dependency_pom_file unless @dependency_pom_file.nil?

        response = Excon.get(
          "#{maven_repo_dependency_url}/"\
          "#{dependency.version}/"\
          "#{dependency_artifact_id}-#{dependency.version}.pom",
          idempotent: true,
          **SharedHelpers.excon_defaults(headers: auth_headers)
        )

        @dependency_pom_file = Nokogiri::XML(response.body)
      rescue Excon::Error::Timeout
        @dependency_pom_file = Nokogiri::XML("")
      end

      def dependency_artifact_id
        _group_id, artifact_id, _classifier = dependency.name.split(":")

        artifact_id
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
          idempotent: true,
          **SharedHelpers.excon_defaults(headers: auth_headers)
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

      def auth_headers
        @auth_headers ||= Utils::AuthHeadersFinder.new(credentials).auth_headers(maven_repo_url)
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("maven", Dependabot::Maven::MetadataFinder)
