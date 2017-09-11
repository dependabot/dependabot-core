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
          git_data = Excon.get(
            url + "/info/refs?service=git-receive-pack",
            middlewares: SharedHelpers.excon_middleware
          ).body

          line = git_data.lines.find do |l|
            l.include?("refs/heads/#{branch}")
          end

          # TODO: Improve error messaging here: make it clear this is a
          # bad branch (or that we couldn't get the URL)
          raise Dependabot::DependencyFileNotResolvable unless line
          line.split(" ").first.chars.last(40).join
        end

        def branch
          dependency.requirements.first.fetch(:requirement).fetch(:branch)
        end
      end
    end
  end
end
