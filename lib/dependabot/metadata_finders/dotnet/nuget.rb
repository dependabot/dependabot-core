# frozen_string_literal: true

require "nokogiri"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Dotnet
      class Nuget < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          look_up_source_in_nuspec(dependency_nuspec_file)
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
          nuspec.to_s.scan(Source::SOURCE_REGEX) do
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
            **SharedHelpers.excon_defaults
          )

          @dependency_nuspec_file = Nokogiri::XML(response.body)
        end

        def dependency_nuspec_url
          "https://api.nuget.org/v3-flatcontainer/"\
          "#{dependency.name.downcase}/#{dependency.version}/"\
          "#{dependency.name.downcase}.nuspec"
        end
      end
    end
  end
end
