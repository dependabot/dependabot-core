# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/runner_label"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module GithubActions
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      # runner-images tags look like `xcode-27-arm64/20261023.0307`, not `26.04`, so
      # runner PRs link to the image table instead of release notes.
      sig { returns(T.nilable(String)) }
      def homepage_url
        RunnerLabel.dependency?(dependency) ? RunnerLabel::RUNNER_IMAGES_URL : super
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        requirement = dependency.requirements.find(&:source_hash)
        url = requirement&.source_string("url") ||
              "https://#{source_hostname}/#{dependency.name}"
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
