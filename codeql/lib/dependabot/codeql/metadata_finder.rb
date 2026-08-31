# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/source"

module Dependabot
  module Codeql
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      # CodeQL pack names are `<scope>/<pack>` GHCR paths; most map directly
      # onto a `github.com/<scope>/<pack>` repository.
      PACK_NAME = %r{\A(?<scope>[\w.-]+)/(?<pack>[\w.-]+)\z}

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        return unless PACK_NAME.match?(dependency.name)

        Dependabot::Source.from_url("https://github.com/#{dependency.name}")
      end
    end
  end
end

Dependabot::MetadataFinders.register("codeql", Dependabot::Codeql::MetadataFinder)
