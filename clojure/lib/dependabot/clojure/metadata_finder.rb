# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/maven/shared/shared_metadata_finder"
require "dependabot/clojure/file_fetcher"

module Dependabot
  module Clojure
    # Finds the source repository from the artifact's POM, as for Maven.
    class MetadataFinder < Dependabot::Maven::Shared::SharedMetadataFinder
      extend T::Sig

      private

      sig { override.returns(T.class_of(Dependabot::FileFetchers::Base)) }
      def file_fetcher_class
        Dependabot::Clojure::FileFetcher
      end
    end
  end
end

Dependabot::MetadataFinders.register("clojure", Dependabot::Clojure::MetadataFinder)
