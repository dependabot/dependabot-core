# typed: strong
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Opam
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      sig { override.returns(T.nilable(String)) }
      def homepage_url
        # Return opam package page URL
        "https://opam.ocaml.org/packages/#{dependency.name}/"
      end

      sig { override.returns(T.nilable(String)) }
      def releases_text
        # ReleaseFinder requires dependency.version to be present, but some dependencies
        # (like platform constraints) don't have a version. Return nil in those cases.
        return nil if dependency.version.nil?

        super
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        # For opam packages, we don't have a reliable way to get source URLs
        # without dependency files. The opam registry doesn't provide source URLs
        # in a queryable API format.
        # Return nil to use default source discovery from dependency requirements
        nil
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("opam", Dependabot::Opam::MetadataFinder)
