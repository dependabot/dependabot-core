# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Ruby
      class Bundler < Dependabot::MetadataFinders::Base
        SOURCE_KEYS = %w(
          source_code_uri
          homepage_uri
          wiki_uri
          bug_tracker_uri
          documentation_uri
          changelog_uri
          mailing_list_uri
          download_uri
        ).freeze

        def changelog_url
          if new_source_type == "default" || new_source_type == "rubygems"
            if rubygems_listing["changelog_uri"]
              return rubygems_listing["changelog_uri"]
            end
          end

          super
        end

        def homepage_url
          if new_source_type == "default" || new_source_type == "rubygems"
            if rubygems_listing["homepage_uri"]
              return rubygems_listing["homepage_uri"]
            end
          end

          super
        end

        private

        def look_up_source
          case new_source_type
          when "default", "rubygems" then find_source_from_rubygems_listing
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

        def find_source_from_rubygems_listing
          source_url = rubygems_listing.
                       values_at(*SOURCE_KEYS).
                       compact.
                       find { |url| Source.from_url(url) }

          Source.from_url(source_url)
        end

        def find_source_from_git_url
          info = dependency.requirements.map { |r| r[:source] }.compact.first

          url = info[:url] || info.fetch("url")
          Source.from_url(url)
        end

        def rubygems_listing
          return @rubygems_listing unless @rubygems_listing.nil?

          response =
            Excon.get(
              "#{registry_url}api/v1/gems/#{dependency.name}.json",
              headers: registry_auth_headers,
              idempotent: true,
              middlewares: SharedHelpers.excon_middleware
            )

          @rubygems_listing = JSON.parse(response.body)
        rescue JSON::ParserError
          @rubygems_listing = {}
        end

        def registry_url
          return "https://rubygems.org/" if new_source_type == "default"

          info = dependency.requirements.map { |r| r[:source] }.compact.first
          info[:url] || info.fetch("url")
        end

        def registry_auth_headers
          return {} unless new_source_type == "rubygems"

          token =
            credentials.
            find { |cred| registry_url.include?(cred["host"]) }&.
            fetch("token")

          return {} unless token

          token += ":" unless token.include?(":")
          { "Authorization" => "Basic #{Base64.encode64(token).chomp}" }
        end
      end
    end
  end
end
