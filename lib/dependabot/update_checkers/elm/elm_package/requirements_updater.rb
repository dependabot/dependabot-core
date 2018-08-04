# frozen_string_literal: true

require "dependabot/utils/elm/version"
require "dependabot/utils/elm/requirement"
require "dependabot/update_checkers/elm/elm_package"

module Dependabot
  module UpdateCheckers
    module Elm
      class ElmPackage
        class RequirementsUpdater
          RANGE_REQUIREMENT_REGEX = /(\d+\.\d+\.\d+) <= v < (\d+\.\d+\.\d+)/

          def initialize(requirements:, latest_resolvable_version:)
            @requirements = requirements

            return unless latest_resolvable_version
            unless Utils::Elm::Version.correct?(latest_resolvable_version)
              return
            end
            @latest_resolvable_version =
              Utils::Elm::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            if @latest_resolvable_version
              requirements.map do |req|
                requirement = update_requirement(
                  req[:requirement],
                  @latest_resolvable_version
                )

                {
                  requirement: requirement,
                  groups: nil,
                  source: nil,
                  file: req[:file]
                }
              end
            else
              requirements
            end
          end

          private

          attr_reader :requirements, :latest_resolvable_version

          def update_requirement(old_req, new_version)
            if Utils::Elm::Requirement.new(old_req).satisfied_by?(new_version)
              old_req
            elsif (match = RANGE_REQUIREMENT_REGEX.match(old_req))
              require_range(match[1], new_version)
            else
              require_exactly(new_version)
            end
          end

          def require_range(minimum, version)
            major, _minor, _patch = version.to_s.split(".").map(&:to_i)
            "#{minimum} <= v < #{major + 1}.0.0"
          end

          def require_exactly(version)
            "#{version} <= v <= #{version}"
          end
        end
      end
    end
  end
end
