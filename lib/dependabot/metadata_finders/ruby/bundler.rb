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
          source_url = rubygems_listing.
                       values_at(*SOURCE_KEYS).
                       compact.
                       find { |url| url =~ SOURCE_REGEX }

          return nil unless source_url
          source_url.match(SOURCE_REGEX).named_captures
        end

        def look_up_changelog_url
          if rubygems_listing["changelog_uri"]
            return rubygems_listing["changelog_uri"]
          end

          super
        end

        def rubygems_listing
          return @rubygems_listing unless @rubygems_listing.nil?

          # Unless we're using the default source (i.e., no source was
          # specified), return early. In future we should check for metadata
          # at the custom source's URL, but we'll need to store that at parse
          # time to do so.
          unless dependency.requirements.all? { |r| r.fetch(:source).nil? }
            return @rubygems_listing = {}
          end

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
