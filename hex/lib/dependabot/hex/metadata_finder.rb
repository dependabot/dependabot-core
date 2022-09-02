# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module Hex
    class MetadataFinder < Dependabot::MetadataFinders::Base
      SOURCE_KEYS = %w(
        GitHub Github github
        GitLab Gitlab gitlab
        BitBucket Bitbucket bitbucket
        Source source
      ).freeze

      private

      def look_up_source
        case new_source_type
        when "default" then find_source_from_hex_listing
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

      def find_source_from_hex_listing
        potential_source_urls =
          SOURCE_KEYS.
          filter_map { |key| hex_listing.dig("meta", "links", key) }

        source_url = potential_source_urls.find { |url| Source.from_url(url) }
        Source.from_url(source_url)
      end

      def find_source_from_git_url
        info = dependency.requirements.filter_map { |r| r[:source] }.first

        url = info[:url] || info.fetch("url")
        Source.from_url(url)
      end

      def hex_listing
        return @hex_listing unless @hex_listing.nil?

        response = Dependabot::RegistryClient.get(url: "https://hex.pm/api/packages/#{dependency.name}")
        @hex_listing = JSON.parse(response.body)
      end
    end
  end
end

Dependabot::MetadataFinders.register("hex", Dependabot::Hex::MetadataFinder)
