# frozen_string_literal: true

require "dependabot/update_checkers/php/composer"

module Dependabot
  module UpdateCheckers
    module Php
      class Composer
        class RequirementsUpdater
          VERSION_REGEX = /[0-9]+(?:\.[a-zA-Z0-9]+)*/

          attr_reader :requirements, :existing_version,
                      :latest_version, :latest_resolvable_version

          def initialize(requirements:, existing_version:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements

            @latest_version = Gem::Version.new(latest_version) if latest_version

            if existing_version
              @existing_version = Gem::Version.new(existing_version)
            end

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Gem::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            return requirements unless latest_resolvable_version

            requirements.map { |req| updated_app_requirement(req) }
          end

          private

          def updated_app_requirement(req)
            current_requirement = req[:requirement]

            updated_requirement =
              current_requirement.
              sub(VERSION_REGEX) do |old_version|
                precision = old_version.split(".").count
                latest_resolvable_version.to_s.
                  split(".").
                  first(precision).
                  join(".")
              end

            req.merge(requirement: updated_requirement)
          end
        end
      end
    end
  end
end
