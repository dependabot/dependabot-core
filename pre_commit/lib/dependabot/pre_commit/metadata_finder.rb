# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module PreCommit
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        requirement = dependency.requirements.find(&:source_hash)
        url = requirement&.source_string("url") ||
              requirement&.source_string("repo_url") ||
              dependency.name
        Source.from_url(url)
      end
    end
  end
end

Dependabot::MetadataFinders.register("pre_commit", Dependabot::PreCommit::MetadataFinder)
