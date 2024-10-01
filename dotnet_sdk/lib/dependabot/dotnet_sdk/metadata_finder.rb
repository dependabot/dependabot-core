# typed: strong
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module DotnetSdk
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        # TODO: Where to link to?
        nil
      end
    end
  end
end

Dependabot::MetadataFinders.register("dotnet_sdk", Dependabot::DotnetSdk::MetadataFinder)
