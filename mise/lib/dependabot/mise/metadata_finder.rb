# typed: strong
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Mise
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        # Mise tools can come from various sources (GitHub, npm, cargo, etc.)
        # We don't attempt to look up sources automatically
        nil
      end
    end
  end
end

Dependabot::MetadataFinders.register("mise", Dependabot::Mise::MetadataFinder)
