# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module Puppet
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        case new_source_type
        when "default" then find_source_from_puppet_forge_listing
        when "git" then find_source_from_git_url
        else raise "Unexpected source type: #{new_source_type}"
        end
      end

      def new_source_type
        sources =
          dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

        return "default" if sources.empty?
        raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

        sources.first[:type] || sources.first.fetch("type")
      end

      def find_source_from_puppet_forge_listing
        current_release_metadata =
          puppet_forge_details.dig("current_release", "metadata")

        potential_source_urls = [
          current_release_metadata&.fetch("source", nil),
          current_release_metadata&.fetch("project_page", nil),
          current_release_metadata&.fetch("issues_url", nil),
          puppet_forge_details&.fetch("homepage_url", nil),
          puppet_forge_details&.fetch("issues_url", nil)
        ].compact

        source_url = potential_source_urls.find { |url| Source.from_url(url) }
        Source.from_url(source_url)
      end

      def find_source_from_git_url
        info = dependency.requirements.map { |r| r[:source] }.compact.first

        url = info[:url] || info.fetch("url")
        Source.from_url(url)
      end

      def puppet_forge_details
        return @puppet_forge_details unless @puppet_forge_details.nil?

        response = Excon.get(
          puppet_forge_url(dependency.name),
          headers: { "User-Agent" => "dependabot-puppet/0.1.0" },
          idempotent: true,
          **SharedHelpers.excon_defaults
        )

        @puppet_forge_details = JSON.parse(response.body)
      rescue JSON::ParserError, Excon::Error::Timeout
        @puppet_forge_details = {}
      end

      def puppet_forge_url(module_name)
        "https://forgeapi.puppet.com/v3/modules/#{module_name}"\
        "?exclude_fields=readme,license,changelog,reference"
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("puppet", Dependabot::Puppet::MetadataFinder)
