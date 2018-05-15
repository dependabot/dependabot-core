# frozen_string_literal: true

require "nokogiri"
require "dependabot/metadata_finders/base"
require "dependabot/file_parsers/java/maven"
require "dependabot/file_parsers/java/maven/repositories_finder"

module Dependabot
  module MetadataFinders
    module Java
      class Maven < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          potential_source_urls = [
            pom_file.at_css("project > url")&.content,
            pom_file.at_css("project > scm > url")&.content,
            pom_file.at_css("project > issueManagement > url")&.content
          ].compact

          source_url = potential_source_urls.find { |url| Source.from_url(url) }
          source_url ||= source_from_anywhere_in_pom
          source_url = substitute_property_in_source_url(source_url)

          Source.from_url(source_url)
        end

        def substitute_property_in_source_url(source_url)
          return unless source_url
          return source_url unless source_url.include?("${")

          regex = FileParsers::Java::Maven::PROPERTY_REGEX
          property_name = source_url.match(regex).named_captures["property"]
          doc = pom_file.dup
          doc.remove_namespaces!
          nm = property_name.sub(/^pom\./, "").sub(/^project\./, "")
          property_value =
            loop do
              candidate_node =
                doc.at_xpath("/project/#{nm}") ||
                doc.at_xpath("/project/properties/#{nm}") ||
                doc.at_xpath("/project/profiles/profile/properties/#{nm}")
              break candidate_node.content if candidate_node
              break unless nm.include?(".")
              nm = nm.sub(".", "/")
            end

          source_url.gsub("${#{property_name}}", property_value)
        end

        def source_from_anywhere_in_pom
          github_urls = []
          pom_file.to_s.scan(Source::SOURCE_REGEX) do
            github_urls << Regexp.last_match.to_s
          end

          github_urls.find do |url|
            repo = Source.from_url(url).repo
            repo.end_with?(dependency.name.split(":").last)
          end
        end

        def pom_file
          return @pom_file unless @pom_file.nil?

          artifact_id = dependency.name.split(":").last
          response = Excon.get(
            "#{maven_repo_dependency_url}/"\
            "#{dependency.version}/"\
            "#{artifact_id}-#{dependency.version}.pom",
            headers: auth_details,
            idempotent: true,
            omit_default_port: true,
            middlewares: SharedHelpers.excon_middleware
          )

          @pom_file = Nokogiri::XML(response.body)
        end

        def maven_repo_url
          source = dependency.requirements.
                   find { |r| r&.fetch(:source) }&.fetch(:source)

          source&.fetch(:url, nil) ||
            source&.fetch("url") ||
            FileParsers::Java::Maven::RepositoriesFinder::CENTRAL_REPO_URL
        end

        def maven_repo_dependency_url
          group_id, artifact_id = dependency.name.split(":")

          "#{maven_repo_url}/#{group_id.tr('.', '/')}/#{artifact_id}"
        end

        def auth_details
          cred = credentials.select { |c| c["type"] == "maven_repository" }.
                 find { |c| c.fetch("url").gsub(%r{/+$}, "") == maven_repo_url }
          return {} unless cred

          token = cred.fetch("username") + ":" + cred.fetch("password")
          encoded_token = Base64.encode64(token).chomp
          { "Authorization" => "Basic #{encoded_token}" }
        end
      end
    end
  end
end
