# frozen_string_literal: true

require "excon"
require "python_requirement_line_parser"
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

        def updated_requirements
          return dependency.requirements unless latest_resolvable_version

          dependency.requirements.map do |req|
            updated_requirement_string =
              req[:requirement].sub(PythonRequirementLineParser::VERSION) do |v|
                precision = v.split(".").count
                latest_resolvable_version.to_s.
                  split(".").
                  first(precision).
                  join(".")
              end

            req.merge(requirement: updated_requirement_string)
          end
        end

        private

        def fetch_latest_version
          # TODO: Support private repos, as described at
          # https://gemfury.com/help/pypi-server#requirements-txt
          pypi_response = Excon.get(
            dependency_url,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          if Gem::Version.new(dependency.version).prerelease?
            Gem::Version.new(JSON.parse(pypi_response.body)["info"]["version"])
          else
            versions = JSON.parse(pypi_response.body).fetch("releases").keys
            versions = versions.map do |v|
              begin
                Gem::Version.new(v)
              rescue ArgumentError
                nil
              end
            end.compact
            versions.reject!(&:prerelease?)
            versions.sort.last
          end
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
