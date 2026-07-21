# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/github_actions/constants"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module GithubActions
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        requirement = dependency.requirements.find(&:source)

        url =
          if requirement.nil?
            "https://#{source_hostname}/#{dependency.name}"
          else
            source_url = requirement.source_string(:url)
            raise TypeError, "Expected dependency source URL to be a String" unless source_url

            source_url
          end
        Source.from_url(url)
      end

      sig { returns(String) }
      def source_hostname
        ghe_cred = credentials.find { |c| c["type"] == "git_source" && c["host"] != GITHUB_COM }
        ghe_cred&.fetch("host", nil) || GITHUB_COM
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("github_actions", Dependabot::GithubActions::MetadataFinder)
