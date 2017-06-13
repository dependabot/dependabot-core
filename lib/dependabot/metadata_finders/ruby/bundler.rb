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

        def rubygems_listing
          return @rubygems_listing unless @rubygems_listing.nil?

          Gems.info(dependency.name)
        rescue JSON::ParserError
          # Replace with Gems::NotFound error if/when
          # https://github.com/rubygems/gems/pull/38 is merged.
          {}
        end
      end
    end
  end
end
