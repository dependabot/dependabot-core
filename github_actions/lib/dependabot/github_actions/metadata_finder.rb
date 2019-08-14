# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module GithubActions
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        info = dependency.requirements.map { |r| r[:source] }.compact.first

        url = info[:url] || info.fetch("url")
        Source.from_url(url)
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("github_actions", Dependabot::GithubActions::MetadataFinder)
