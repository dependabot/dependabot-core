# frozen_string_literal: true
require "gems"
require "bump/dependency_metadata_finders/base"
require "bump/shared_helpers"

module Bump
  module DependencyMetadataFinders
    class Cocoa < Base
      GITHUB_LINK_REGEX = /class="github-link".*?#{GITHUB_REGEX}">/m

      private

      def look_up_github_repo
        cocoapods_listing.match(GITHUB_LINK_REGEX)&.[](:repo)
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
