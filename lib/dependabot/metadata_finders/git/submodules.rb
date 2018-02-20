# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Git
      class Submodules < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          url = dependency.requirements.first.fetch(:source)[:url] ||
                dependency.requirements.first.fetch(:source).fetch("url")

          Source.from_url(url)
        end
      end
    end
  end
end
