# frozen_string_literal: true
require "gems"
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

        private

        def look_up_source
          case source_type
          when "default" then find_source_from_rubygems_listing
          when "git" then find_source_from_git_url
          when "rubygems" then nil # Private rubygems server
          else raise "Unexpected source type: #{source_type}"
          end
        end

        def look_up_changelog_url
          if source_type == "default" && rubygems_listing["changelog_uri"]
            return rubygems_listing["changelog_uri"]
          end

          if source_type == "git"
            return nil # Changelog won't be relevant for git commit bumps
          end

          super
        end

        def source_type
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
                       find { |url| url =~ SOURCE_REGEX }

          return nil unless source_url
          source_url.match(SOURCE_REGEX).named_captures
        end

        def find_source_from_git_url
          source_details = dependency.requirements.
                           map { |r| r.fetch(:source) }.
                           compact.first

          source_url = source_details[:url] || source_details.fetch("url")
          source_url.match(SOURCE_REGEX).named_captures
        end

        def rubygems_listing
          return @rubygems_listing unless @rubygems_listing.nil?

          @rubygems_listing = Gems.info(dependency.name)
        rescue JSON::ParserError
          # Replace with Gems::NotFound error if/when
          # https://github.com/rubygems/gems/pull/38 is merged.
          @rubygems_listing = {}
        end
      end
    end
  end
end
