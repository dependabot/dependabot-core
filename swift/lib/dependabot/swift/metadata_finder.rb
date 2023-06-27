# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Swift
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        raise NotImplementedError
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("swift", Dependabot::Swift::MetadataFinder)
