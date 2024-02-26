# typed: true
# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module Cargo
    class MetadataFinder < Dependabot::MetadataFinders::Base
      SOURCE_KEYS = %w(repository homepage documentation).freeze
      CRATES_IO_API = "https://crates.io/api/v1/crates"

      private

      def look_up_source
        case new_source_type
        when "default" then find_source_from_crates_listing
        when "registry" then find_source_from_crates_listing
        when "git" then find_source_from_git_url
        else raise "Unexpected source type: #{new_source_type}"
        end
      end

      def new_source_type
        dependency.source_type
      end

      def find_source_from_crates_listing
        potential_source_urls =
          SOURCE_KEYS
          .filter_map { |key| crates_listing.dig("crate", key) }

        source_url = potential_source_urls.find { |url| Source.from_url(url) }
        Source.from_url(source_url)
      end

      def find_source_from_git_url
        info = dependency.requirements.filter_map { |r| r[:source] }.first

        url = info[:url] || info.fetch("url")
        Source.from_url(url)
      end

      def crates_listing
        return @crates_listing unless @crates_listing.nil?

        info = dependency.requirements.filter_map { |r| r[:source] }.first
        index = (info && info[:index]) || CRATES_IO_API

        # Default request headers
        hdrs = { "User-Agent" => "Dependabot (dependabot.com)" }

        if index != CRATES_IO_API
          # Add authentication headers if credentials are present for this registry
          credentials.find { |cred| cred["type"] == "cargo_registry" && cred["registry"] == info[:name] }&.tap do |cred|
            hdrs["Authorization"] = "Token #{cred['token']}"
          end
        end

        url = metadata_fetch_url(dependency, index)

        response = Excon.get(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults(headers: hdrs)
        )

        @crates_listing = JSON.parse(response.body)
      end

      def metadata_fetch_url(dependency, index)
        return "#{index}/#{dependency.name}" if index == CRATES_IO_API

        # Determine cargo's index file path for the dependency
        index = index.delete_prefix("sparse+")
        name_length = dependency.name.length
        dependency_path = case name_length
                          when 1, 2
                            "#{name_length}/#{dependency.name}"
                          when 3
                            "#{name_length}/#{dependency.name[0..1]}/#{dependency.name}"
                          else
                            "#{dependency.name[0..1]}/#{dependency.name[2..3]}/#{dependency.name}"
                          end

        "#{index}#{'/' unless index.end_with?('/')}#{dependency_path}"
      end
    end
  end
end

Dependabot::MetadataFinders.register("cargo", Dependabot::Cargo::MetadataFinder)
