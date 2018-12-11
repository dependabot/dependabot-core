# frozen_string_literal: true

require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module Elm
      class ElmPackage < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          # For Elm 0.18 an elm-package is guaranteed to be `owner/name`
          # on github. For 0.19 a lot will change, including the name of
          # the dependency file, so I won't try to build something more
          # sophisticated here for now.
          Source.from_url("https://github.com/" + dependency.name)
        end
      end
    end
  end
end
