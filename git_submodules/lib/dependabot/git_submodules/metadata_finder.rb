# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module GitSubmodules
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        url = dependency.requirements.first&.fetch(:source)&.fetch(:url) ||
              dependency.requirements.first&.fetch(:source)&.fetch("url")

        Source.from_url(url)
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("submodules", Dependabot::GitSubmodules::MetadataFinder)
