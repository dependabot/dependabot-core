# frozen_string_literal: true
require "dependabot/update_checkers/base"
require "dependabot/metadata_finders/base"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Git
      class Submodules < Dependabot::UpdateCheckers::Base
        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          # Resolvability isn't an issue for sub-modules!
          latest_version
        end

        def updated_requirements
          # Submodule requirements are the URL and branch to use for the
          # submodule. We never want to update either.
          dependency.requirements
        end

        def needs_update?
          # We're comparing commit SHAs, so just look for difference
          latest_version != dependency.version
        end

        private

        def fetch_latest_version
          # Hit GitHub to get the latest commit sha for the submodule
          # TODO: Support Bitbucket and GitLab
          github_client.ref(github_repo, "heads/#{branch}").object.sha
        rescue Octokit::NotFound
          raise Dependabot::DependencyFileNotResolvable
        end

        def github_repo
          url = dependency.requirements.first.fetch(:requirement).fetch(:url)
          regex_match = url.match(MetadataFinders::Base::SOURCE_REGEX)

          unless regex_match
            raise "Submodule URL didn't match any known sources: #{url}"
          end

          unless regex_match.named_captures.fetch("host") == "github"
            raise "Submodule has non-GitHub source: #{url}"
          end

          regex_match.named_captures.fetch("repo")
        end

        def branch
          dependency.requirements.first.fetch(:requirement).fetch(:branch)
        end

        def github_client
          @github_client ||=
            Octokit::Client.new(access_token: github_access_token)
        end
      end
    end
  end
end
