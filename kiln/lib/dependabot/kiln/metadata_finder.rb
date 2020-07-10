# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Kiln
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        nil
      end

    end
  end
end

Dependabot::MetadataFinders.
    register("kiln", Dependabot::Kiln::MetadataFinder)

