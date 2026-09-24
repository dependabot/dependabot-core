# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/source"

module Dependabot
  module Apm
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        Source.from_url(dependency.requirements.first&.source_string("url"))
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("apm", Dependabot::Apm::MetadataFinder)
