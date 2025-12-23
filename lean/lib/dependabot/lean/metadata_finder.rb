# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/lean"

module Dependabot
  module Lean
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        # For the Lean toolchain dependency, return the Lean repo
        return Dependabot::Source.from_url(LEAN_GITHUB_URL) unless lake_package?

        # For Lake packages, return the package's source URL
        source_url = dependency.source_details&.fetch(:url, nil)
        return nil unless source_url

        Dependabot::Source.from_url(source_url)
      end

      sig { returns(T::Boolean) }
      def lake_package?
        source_details = dependency.source_details
        return false unless source_details

        source_details[:type] == "git"
      end
    end
  end
end

Dependabot::MetadataFinders.register("lean", Dependabot::Lean::MetadataFinder)
