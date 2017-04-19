# frozen_string_literal: true
require "excon"
require "bump/update_checkers/base"
require "bump/shared_helpers"

module Bump
  module UpdateCheckers
    class Python < Base
      def latest_version
        @latest_version ||=
          begin
            pypi_response = Excon.get(
              dependency_url,
              middlewares: SharedHelpers.excon_middleware
            )

            JSON.parse(pypi_response.body)["info"]["version"]
          end
      end

      def dependency_version
        Gem::Version.new(dependency.version)
      end

      def language
        "python"
      end

      def dependency_url
        "https://pypi.python.org/pypi/#{dependency.name}/json"
      end
    end
  end
end
