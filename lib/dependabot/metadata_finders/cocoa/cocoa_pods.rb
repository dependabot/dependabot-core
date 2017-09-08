# frozen_string_literal: true
require "excon"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module Cocoa
      class CocoaPods < Dependabot::MetadataFinders::Base
        GITHUB_LINK_REGEX = /class="github-link".*?#{SOURCE_REGEX}">/m

        private

        def look_up_source
          cocoapods_listing.match(GITHUB_LINK_REGEX)&.named_captures
        end

        def cocoapods_listing
          return @cocoapods_listing unless @cocoapods_listing.nil?

          # CocoaPods doesn't have a JSON API, so we get the inline HTML from
          # their site... :(
          url = "https://cocoapods.org/pods/#{dependency.name}/inline"
          response = Excon.get(url, middlewares: SharedHelpers.excon_middleware)

          @cocoapods_listing = response.body
        end
      end
    end
  end
end
