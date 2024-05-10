# typed: strong
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Silent
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      sig { returns(String) }
      def homepage_url
        ""
      end

      private

      sig { override.returns(Dependabot::Source) }
      def look_up_source
        Dependabot::Source.new(
          provider: "example",
          hostname: "example.com",
          api_endpoint: "https://example.com/api/v3",
          repo: dependency.name,
          directory: nil,
          branch: nil
        )
      end
    end
  end
end
