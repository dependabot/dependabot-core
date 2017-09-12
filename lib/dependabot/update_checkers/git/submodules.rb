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
          url = dependency.requirements.first.fetch(:requirement).fetch(:url)
          url += ".git" unless url.end_with?(".git")
          git_data = Excon.get(
            url + "/info/refs?service=git-upload-pack",
            middlewares: SharedHelpers.excon_middleware
          )

          unless git_data.status == 200
            raise Dependabot::GitDependenciesNotReachable, [url]
          end

          line = git_data.body.lines.find do |l|
            l.include?("refs/heads/#{branch}")
          end

          return line.split(" ").first.chars.last(40).join if line
          raise Dependabot::GitDependencyReferenceNotFound, dependency.name
        end

        def branch
          dependency.requirements.first.fetch(:requirement).fetch(:branch)
        end
      end
    end
  end
end
