# frozen_string_literal: true
require "json"
require "excon"
require "bump/update_checkers/base"
require "bump/shared_helpers"

module Bump
  module UpdateCheckers
    class JavaScript < Base
      def latest_version
        @latest_version ||=
          begin
            npm_response = Excon.get(
              dependency_url,
              middlewares: SharedHelpers.excon_middleware
            )

            JSON.parse(npm_response.body)["dist-tags"]["latest"]
          end
      end

      def dependency_version
        Gem::Version.new(dependency.version)
      end

      private

      def dependency_url
        # NPM registry expects slashes to be escaped
        path = dependency.name.gsub("/", "%2F")
        "http://registry.npmjs.org/#{path}"
      end

      def language
        "javascript"
      end
    end
  end
end
