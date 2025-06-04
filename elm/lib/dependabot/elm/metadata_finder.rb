# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/source"

module Dependabot
  module Elm
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
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

Dependabot::MetadataFinders.register("elm", Dependabot::Elm::MetadataFinder)
