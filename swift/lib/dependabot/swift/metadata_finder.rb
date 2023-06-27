# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Swift
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        case new_source_type
        when "git" then find_source_from_git_url
        when "registry" then find_source_from_registry
        else raise "Unexpected source type: #{new_source_type}"
        end
      end

      def new_source_type
        dependency.source_type
      end

      def find_source_from_git_url
        info = dependency.source_details

        url = info[:url] || info.fetch("url")
        Source.from_url(url)
      end

      def find_source_from_registry
        raise NotImplementedError
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("swift", Dependabot::Swift::MetadataFinder)
