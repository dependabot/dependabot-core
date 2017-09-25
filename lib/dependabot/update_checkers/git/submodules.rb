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

        private

        def fetch_latest_version
          requirement = dependency.requirements.first.fetch(:requirement)
          url = requirement.fetch(:url)
          url += ".git" unless url.end_with?(".git")

          response = Excon.get(url + "/info/refs?service=git-upload-pack",
                               middlewares: SharedHelpers.excon_middleware)

          success = response.status == 200
          raise Dependabot::GitDependenciesNotReachable, [url] unless success

          branch_ref = "refs/heads/#{requirement.fetch(:branch)}"
          line = response.body.lines.find { |l| l.include?(branch_ref) }

          return line.split(" ").first.chars.last(40).join if line
          raise Dependabot::GitDependencyReferenceNotFound, dependency.name
        end
      end
    end
  end
end
