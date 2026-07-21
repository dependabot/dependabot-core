# typed: strict
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
        info = dependency.requirements.filter_map(&:source).first

        url =
          if info.nil?
            dependency.name
          else
            values = [info[:url], info[:repo_url], info["url"], info["repo_url"]]
            value = values.find { |candidate| candidate.is_a?(String) }
            value.is_a?(String) ? value : dependency.name
          end
        Source.from_url(url)
      end
    end
  end
end

Dependabot::MetadataFinders.register("pre_commit", Dependabot::PreCommit::MetadataFinder)
