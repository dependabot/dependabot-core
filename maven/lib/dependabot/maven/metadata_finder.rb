# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/maven/file_fetcher"
require "dependabot/maven/file_parser"
require "dependabot/maven/file_parser/repositories_finder"
require "dependabot/maven/utils/auth_headers_finder"
require "dependabot/registry_client"
require "sorbet-runtime"

module Dependabot
  module Maven
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig
      DOT_SEPARATOR_REGEX = %r{\.(?!\d+([.\/_\-]|$)+)}

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        tmp_source = look_up_source_in_pom(dependency_pom_file)
        return tmp_source if tmp_source

        return unless (parent = parent_pom_file(dependency_pom_file))

        tmp_source = look_up_source_in_pom(parent)
        return unless tmp_source

        return tmp_source if tmp_source.repo.end_with?(T.must(dependency_artifact_id))

        tmp_source if repo_has_subdir_for_dep?(tmp_source)
      end

      sig { params(tmp_source: Dependabot::Source).returns(T::Boolean) }
      def repo_has_subdir_for_dep?(tmp_source)
        @repo_has_subdir_for_dep ||= T.let({}, T.nilable(T::Hash[Dependabot::Source, T::Boolean]))
        return T.must(@repo_has_subdir_for_dep[tmp_source]) if @repo_has_subdir_for_dep.key?(tmp_source)

        fetcher =
          Dependabot::Maven::FileFetcher.new(source: tmp_source, credentials: credentials)

        @repo_has_subdir_for_dep[tmp_source] =
          fetcher.send(:repo_contents, raise_errors: false)
                 .select { |f| f.type == "dir" }
                 .any? { |f| T.must(dependency_artifact_id).end_with?(f.name) }
      rescue Dependabot::BranchNotFound
        # If we are attempting to find a branch, we should fail over to the default branch and retry once only
        unless tmp_source.branch.to_s.empty?
          tmp_source.branch = nil
          retry
        end
        T.must(@repo_has_subdir_for_dep)[tmp_source] = false
      rescue Dependabot::RepoNotFound
        T.must(@repo_has_subdir_for_dep)[tmp_source] = false
      end

      sig { params(pom: Nokogiri::XML::Document).returns(T.nilable(Dependabot::Source)) }
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

      sig { params(source_url: T.nilable(String), pom: Nokogiri::XML::Document).returns(T.nilable(String)) }
      def substitute_properties_in_source_url(source_url, pom)
        return unless source_url
        return source_url unless source_url.include?("${")

        regex = Maven::FileParser::PROPERTY_REGEX
        property_name = T.must(source_url.match(regex)).named_captures["property"]
        doc = pom.dup
        doc.remove_namespaces!
        nm = T.must(property_name).sub(/^pom\./, "").sub(/^project\./, "")
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

      sig { params(pom: T.any(String, Nokogiri::XML::Document)).returns(T.nilable(String)) }
      def source_from_anywhere_in_pom(pom)
        github_urls = []
        pom.to_s.scan(Source::SOURCE_REGEX) do
          github_urls << Regexp.last_match.to_s
        end

        github_urls.find do |url|
          repo = T.must(Source.from_url(url)).repo
          repo.end_with?(T.must(dependency_artifact_id))
        end
      end

      sig { returns(Nokogiri::XML::Document) }
      def dependency_pom_file
        @dependency_pom_file = T.let(nil, T.nilable(Nokogiri::XML::Document))

        return @dependency_pom_file unless @dependency_pom_file.nil?

        response = Dependabot::RegistryClient.get(
          url: "#{maven_repo_dependency_url}/#{dependency.version}/#{dependency_artifact_id}-#{dependency.version}.pom",
          headers: auth_headers
        )

        @dependency_pom_file = Nokogiri::XML(response.body)
      rescue Excon::Error::Timeout
        @dependency_pom_file = Nokogiri::XML("")
      end

      sig { returns(T.nilable(String)) }
      def dependency_artifact_id
        _group_id, artifact_id = dependency.name.split(":")

        artifact_id
      end

      sig { params(pom: Nokogiri::XML::Document).returns(T.nilable(Nokogiri::XML::Document)) }
      def parent_pom_file(pom)
        doc = pom.dup
        doc.remove_namespaces!
        group_id = doc.at_xpath("/project/parent/groupId")&.content&.strip
        artifact_id =
          doc.at_xpath("/project/parent/artifactId")&.content&.strip
        version = doc.at_xpath("/project/parent/version")&.content&.strip

        return unless artifact_id && group_id && version

        url = "#{maven_repo_url}/#{group_id.tr('.', '/')}/#{artifact_id}/" \
              "#{version}/" \
              "#{artifact_id}-#{version}.pom"

        response = Dependabot::RegistryClient.get(
          url: T.must(substitute_properties_in_source_url(url, pom)),
          headers: auth_headers
        )

        Nokogiri::XML(response.body)
      end

      sig { returns(String) }
      def maven_repo_url
        source = dependency.requirements
                           .find { |r| r.fetch(:source) }&.fetch(:source)

        source&.fetch(:url, nil) ||
          source&.fetch("url") ||
          Maven::FileParser::RepositoriesFinder.new(credentials: credentials, pom_fetcher: nil).central_repo_url
      end

      sig { returns(String) }
      def maven_repo_dependency_url
        group_id, artifact_id = dependency.name.split(":")

        "#{maven_repo_url}/#{T.must(group_id).tr('.', '/')}/#{artifact_id}"
      end

      sig { returns(T::Hash[String, String]) }
      def auth_headers
        @auth_headers ||= T.let(Utils::AuthHeadersFinder.new(credentials).auth_headers(maven_repo_url),
                                T.nilable(T::Hash[String, String]))
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("maven", Dependabot::Maven::MetadataFinder)
