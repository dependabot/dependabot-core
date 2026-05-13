# typed: strict
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/maven/shared/shared_metadata_finder"
require "dependabot/sbt/file_fetcher"
require "sorbet-runtime"

module Dependabot
  module Sbt
    class MetadataFinder < Dependabot::Maven::Shared::SharedMetadataFinder
      extend T::Sig

      private

      sig { override.returns(T.class_of(Dependabot::FileFetchers::Base)) }
      def file_fetcher_class
        Dependabot::Sbt::FileFetcher
      end
    end
  end
end

Dependabot::MetadataFinders.register("sbt", Dependabot::Sbt::MetadataFinder)
