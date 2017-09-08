# frozen_string_literal: true
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Git
      class Submodules < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          url = dependency.requirements.first.fetch(:requirement).fetch(:url)

          return nil unless url.match?(SOURCE_REGEX)
          url.match(SOURCE_REGEX).named_captures
        end
      end
    end
  end
end
