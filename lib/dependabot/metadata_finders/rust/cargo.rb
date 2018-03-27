# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module Rust
      class Cargo < Dependabot::MetadataFinders::Base
        SOURCE_KEYS = %w(repository homepage documentation).freeze

        private

        def look_up_source
          case new_source_type
          when "default" then find_source_from_crates_listing
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

        def find_source_from_crates_listing
          potential_source_urls =
            SOURCE_KEYS.
            map { |key| crates_listing.dig("crate", key) }.
            compact

          source_url = potential_source_urls.find { |url| Source.from_url(url) }
          Source.from_url(source_url)
        end

        def find_source_from_git_url
          info = dependency.requirements.map { |r| r[:source] }.compact.first

          url = info[:url] || info.fetch("url")
          Source.from_url(url)
        end

        def crates_listing
          return @crates_listing unless @crates_listing.nil?

          response = Excon.get(
            "https://crates.io/api/v1/crates/#{dependency.name}",
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          @crates_listing = JSON.parse(response.body)
        end
      end
    end
  end
end
