# frozen_string_literal: true
require "excon"
require "bump/update_checkers/base"

module Bump
  module UpdateCheckers
    class Python < Base
      def latest_version
        @latest_version ||= Gem::Version.new(fetch_latest_version)
      end

      private

      def fetch_latest_version
        pypi_response = Excon.get(
          dependency_url,
          middlewares: SharedHelpers.excon_middleware
        )

        JSON.parse(pypi_response.body)["info"]["version"]
      end

      def dependency_url
        "https://pypi.python.org/pypi/#{dependency.name}/json"
      end
    end
  end
end
