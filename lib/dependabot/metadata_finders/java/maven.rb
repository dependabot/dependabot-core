# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Java
      class Maven < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          # TODO: return a `Source` object with a github, gitlab or bitbucket
          # host, and details of the repo. Use SOURCE_REGEX (on the base class)
          # to check if any candidate URLs include these (candidate URLs
          # normally come from hitting the registry's API for details of the
          # dependency)
        end
      end
    end
  end
end
