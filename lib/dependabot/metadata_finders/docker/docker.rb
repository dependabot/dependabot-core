# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Docker
      class Docker < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          # TODO: Find a way to add links to PRs
          nil
        end
      end
    end
  end
end
