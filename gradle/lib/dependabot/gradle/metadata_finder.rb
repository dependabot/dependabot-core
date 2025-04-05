# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "sorbet-runtime"

require "dependabot/file_fetchers/base"
require "dependabot/gradle/file_fetcher"
require "dependabot/gradle/file_parser/repositories_finder"
require "dependabot/maven/utils/auth_headers_finder"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module Gradle
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      DOT_SEPARATOR_REGEX = %r{\.(?!\d+([.\/_\-]|$)+)}
      PROPERTY_REGEX      = /\$\{(?<property>.*?)\}/
      KOTLIN_PLUGIN_REPO_PREFIX = "org.jetbrains.kotlin"

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        tmp_source = look_up_source_in_pom(dependency_pom_file)
        return tmp_source if tmp_source

        return unless (parent = parent_pom_file(dependency_pom_file))

        tmp_source = look_up_source_in_pom(parent)
        return unless tmp_source

        artifact = dependency.name.split(":").last
        return tmp_source if tmp_source.repo.end_with?(T.must(artifact))

        tmp_source if repo_has_subdir_for_dep?(tmp_source)
      end

      sig { params(tmp_source: Dependabot::Source).returns(T::Boolean) }
      def repo_has_subdir_for_dep?(tmp_source)
        @repo_has_subdir_for_dep ||= T.let({}, T.nilable(T::Hash[Dependabot::Source, T::Boolean]))
        return T.must(@repo_has_subdir_for_dep[tmp_source]) if @repo_has_subdir_for_dep.key?(tmp_source)

        artifact = dependency.name.split(":").last
        fetcher =
          Dependabot::Gradle::FileFetcher.new(source: tmp_source, credentials: credentials)

        @repo_has_subdir_for_dep[tmp_source] =
          fetcher.send(:repo_contents, raise_errors: false)
                 .select { |f| f.type == "dir" }
                 .any? { |f| artifact&.end_with?(f.name) }
      rescue Dependabot::BranchNotFound
        tmp_source.branch = nil
        retry
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
        source_url = substitute_property_in_source_url(source_url, pom)

        Source.from_url(source_url)
      end

      sig { params(source_url: T.nilable(String), pom: Nokogiri::XML::Document).returns(T.nilable(String)) }
      def substitute_property_in_source_url(source_url, pom)
        return unless source_url
        return source_url unless source_url.include?("${")

        regex = PROPERTY_REGEX
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

        source_url.gsub("${#{property_name}}", property_value)
      end

      sig { params(pom: T.any(String, Nokogiri::XML::Document)).returns(T.nilable(String)) }
      def source_from_anywhere_in_pom(pom)
        github_urls = []
        pom.to_s.scan(Source::SOURCE_REGEX) do
          github_urls << Regexp.last_match.to_s
        end

        github_urls.find do |url|
          repo = T.must(Source.from_url(url)).repo
          repo.end_with?(T.must(dependency.name.split(":").last))
        end
      end

      sig { returns(Nokogiri::XML::Document) }
      def dependency_pom_file
        return @dependency_pom_file unless @dependency_pom_file.nil?

        artifact_id =
          if kotlin_plugin? then "#{KOTLIN_PLUGIN_REPO_PREFIX}.#{dependency.name}.gradle.plugin"
          elsif plugin? then "#{dependency.name}.gradle.plugin"
          else
            dependency.name.split(":").last
          end

        response = Dependabot::RegistryClient.get(
          url: "#{maven_repo_dependency_url}/#{dependency.version}/#{artifact_id}-#{dependency.version}.pom",
          headers: auth_headers
        )

        @dependency_pom_file = T.let(Nokogiri::XML(response.body), T.nilable(Nokogiri::XML::Document))
      rescue Excon::Error::Timeout
        @dependency_pom_file ||= T.let(Nokogiri::XML(""), T.nilable(Nokogiri::XML::Document))
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

        response = Dependabot::RegistryClient.get(
          url: "#{maven_repo_url}/#{group_id.tr('.', '/')}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.pom",
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
          Gradle::FileParser::RepositoriesFinder::CENTRAL_REPO_URL
      end

      sig { returns(String) }
      def maven_repo_dependency_url
        group_id, artifact_id =
          if kotlin_plugin?
            ["#{KOTLIN_PLUGIN_REPO_PREFIX}.#{dependency.name}",
             "#{KOTLIN_PLUGIN_REPO_PREFIX}.#{dependency.name}.gradle.plugin"]
          elsif plugin? then [dependency.name, "#{dependency.name}.gradle.plugin"]
          else
            dependency.name.split(":")
          end

        "#{maven_repo_url}/#{group_id&.tr('.', '/')}/#{artifact_id}"
      end

      sig { returns(T::Boolean) }
      def plugin?
        dependency.requirements.any? { |r| r.fetch(:groups).include? "plugins" }
      end

      sig { returns(T::Boolean) }
      def kotlin_plugin?
        plugin? && dependency.requirements.any? { |r| r.fetch(:groups).include? "kotlin" }
      end

      sig { returns(T::Hash[String, String]) }
      def auth_headers
        @auth_headers ||= T.let(
          Dependabot::Maven::Utils::AuthHeadersFinder.new(credentials).auth_headers(maven_repo_url),
          T.nilable(T::Hash[String, String])
        )
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("gradle", Dependabot::Gradle::MetadataFinder)
