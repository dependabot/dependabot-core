# frozen_string_literal: true
require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip < Dependabot::UpdateCheckers::Base
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
end
