# frozen_string_literal: true
require "excon"
require "bump/update_checkers/base"
require "bump/shared_helpers"

module Bump
  module UpdateCheckers
    class JavaScript < Base
      def latest_version
        @latest_version ||= Gem::Version.new(fetch_latest_version)
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
        "http://registry.npmjs.org/#{path}"
      end
    end
  end
end
