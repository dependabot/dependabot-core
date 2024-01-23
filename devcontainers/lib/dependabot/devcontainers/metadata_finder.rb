# typed: true
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Devcontainers
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        # TODO: Make upstream changes to dev container CLI to point to docs.
        #       Specifically, 'devcontainers features info' can be augmented to expose documentationUrl
        nil
      end
    end
  end
end

Dependabot::MetadataFinders.register("devcontainers", Dependabot::Devcontainers::MetadataFinder)
