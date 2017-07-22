# frozen_string_literal: true
require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip < Dependabot::UpdateCheckers::Base
        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          # pip doesn't (yet) do any dependency resolution. Mad but true.
          # See https://github.com/pypa/pip/issues/988 for details. This should
          # change in pip 10, due in August 2017.
          latest_version
        end

        private

        def fetch_latest_version
          # TODO: Support private repos, as described at
          # https://gemfury.com/help/pypi-server#requirements-txt
          pypi_response = Excon.get(
            dependency_url,
            middlewares: SharedHelpers.excon_middleware
          )

          Gem::Version.new(JSON.parse(pypi_response.body)["info"]["version"])
        rescue JSON::ParserError
          nil
        end

        def dependency_url
          "https://pypi.python.org/pypi/#{dependency.name}/json"
        end
      end
    end
  end
end
