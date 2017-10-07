# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Git
      class Submodules < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          url = dependency.requirements.first.fetch(:source)[:url] ||
                dependency.requirements.first.fetch(source).fetch("url")

          return nil unless url.match?(SOURCE_REGEX)
          url.match(SOURCE_REGEX).named_captures
        end

        def look_up_commits_url
          return unless source_url

          build_compare_commits_url(
            dependency.version,
            dependency.previous_version
          )
        end
      end
    end
  end
end
