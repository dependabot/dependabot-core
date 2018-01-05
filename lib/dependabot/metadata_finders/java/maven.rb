# frozen_string_literal: true

require "nokogiri"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Java
      class Maven < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          potential_source_urls = [
            pom_file.at_css("project url")&.content,
            pom_file.at_css("project scm url")&.content,
            pom_file.at_css("project scm issueManagement")&.content
          ].compact

          source_url = potential_source_urls.find { |url| url =~ SOURCE_REGEX }

          return nil unless source_url
          captures = source_url.match(SOURCE_REGEX).named_captures
          Source.new(host: captures.fetch("host"), repo: captures.fetch("repo"))
        end

        def pom_file
          return @pom_file unless @pom_file.nil?

          artifact_id = dependency.name.split(":").last
          response = Excon.get(
            "#{maven_central_dependency_url}"\
            "#{dependency.version}/"\
            "#{artifact_id}-#{dependency.version}.pom",
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          @pom_file = Nokogiri::XML(response.body)
        end

        def maven_central_dependency_url
          "https://search.maven.org/remotecontent?filepath="\
          "#{dependency.name.gsub(/[:.]/, '/')}/"
        end
      end
    end
  end
end
