# frozen_string_literal: true

require "excon"
require "python_requirement_parser"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip < Dependabot::UpdateCheckers::Base
        require_relative "pip/requirements_updater"

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
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s
          ).updated_requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for pip because they're not
          # relevant (pip doesn't have a resolver). This method always returns
          # false to ensure `updated_dependencies_after_full_unlock` is never
          # called.
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def fetch_latest_version
          versions = available_versions
          versions.reject!(&:prerelease?) unless wants_prerelease?
          versions.sort.last
        rescue JSON::ParserError
          nil
        end

        def wants_prerelease?
          if dependency.version
            return Gem::Version.new(dependency.version).prerelease?
          end

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.split(".").last.match?(/\D/) }
          end
        end

        def available_versions
          # TODO: Support private repos, as described at
          # https://gemfury.com/help/pypi-server#requirements-txt
          pypi_response = Excon.get(
            "https://pypi.python.org/pypi/simple/#{normalised_name}",
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          pypi_response.body.
            scan(%r{<a\s.*?>(.*?)</a>}m).flatten.
            map do |filename|
              version =
                filename.gsub("#{normalised_name}-", "").
                split(/-|(\.tar\.gz)/).
                first
              begin
                Gem::Version.new(version)
              rescue ArgumentError
                nil
              end
            end.compact
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name
          dependency.name.downcase.tr("_", "-").tr(".", "-")
        end
      end
    end
  end
end
