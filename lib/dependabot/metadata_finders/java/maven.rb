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

          source_url = potential_source_urls.find { |url| Source.from_url(url) }
          source_url = substitute_property_in_source_url(source_url)

          Source.from_url(source_url)
        end

        def substitute_property_in_source_url(source_url)
          return unless source_url
          return source_url unless source_url.include?("${")

          property_name = source_url.match(/\$\{(?<name>.*)}/)[:name]
          doc = pom_file.dup
          doc.remove_namespaces!
          property_value =
            if property_name.start_with?("project.")
              path = "//project/#{property_name.gsub(/^project\./, '')}"
              doc.at_xpath(path)&.content ||
                doc.at_xpath("//properties/#{property_name}").content
            else
              doc.at_xpath("//properties/#{property_name}").content
            end

          source_url.gsub("${#{property_name}}", property_value)
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
