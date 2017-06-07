# frozen_string_literal: true
require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class Yarn < Dependabot::UpdateCheckers::Base
        def latest_version
          @latest_version ||= Gem::Version.new(fetch_latest_version)
        end

        def latest_resolvable_version
          # Javascript doesn't have the concept of version conflicts, so the
          # latest version is always resolvable.
          latest_version
        end

        private

        def fetch_latest_version
          npm_response = Excon.get(
            dependency_url,
            middlewares: SharedHelpers.excon_middleware
          )

          JSON.parse(npm_response.body)["dist-tags"]["latest"]
        end

        def dependency_url
          # NPM registry expects slashes to be escaped
          path = dependency.name.gsub("/", "%2F")
          "https://registry.npmjs.org/#{path}"
        end
      end
    end
  end
end
