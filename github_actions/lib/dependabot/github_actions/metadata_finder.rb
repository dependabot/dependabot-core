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
        info = dependency.requirements.filter_map { |r| r[:source] }.first

        url =
          if info.nil?
            "https://#{source_hostname}/#{dependency.name}"
          else
            info[:url] || info.fetch("url")
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
