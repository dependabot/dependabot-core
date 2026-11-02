# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/source"

require "dependabot/nimble/package_index"

module Dependabot
  module Nimble
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      # The repository the package index lists for the package.
      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        url = PackageIndex.new.repository_url(dependency.name)
        url && Source.from_url(url)
      end
    end
  end
end

Dependabot::MetadataFinders.register("nimble", Dependabot::Nimble::MetadataFinder)
