# frozen_string_literal: true

require "dependabot/update_checkers/python/pip"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip
        class RequirementsUpdater
          attr_reader :requirements, :existing_version,
                      :latest_version, :latest_resolvable_version

          def initialize(requirements:, existing_version:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements

            if existing_version
              @existing_version = Gem::Version.new(existing_version)
            end

            @latest_version = Gem::Version.new(latest_version) if latest_version

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Gem::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            requirements.map { |req| updated_requirement(req) }
          end

          private

          def updated_requirement(req)
            return req unless latest_resolvable_version
            return req unless req.fetch(:requirement)
            return req unless req.fetch(:requirement).split(",").count == 1
            return req unless req.fetch(:requirement).start_with?("==")

            updated_requirement_string = req[:requirement].sub(
              PythonRequirementParser::VERSION,
              latest_resolvable_version.to_s
            )

            req.merge(requirement: updated_requirement_string)
          end
        end
      end
    end
  end
end
