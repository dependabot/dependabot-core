# frozen_string_literal: true

#######################################################
# For more details on Maven version constraints, see: #
# https://maven.apache.org/pom.html#Dependencies      #
#######################################################

require "dependabot/update_checkers/java/maven"

module Dependabot
  module UpdateCheckers
    module Java
      class Maven
        class RequirementsUpdater
          VERSION_REGEX = /[0-9]+(?:\.[a-z0-9\-]+)*/

          def initialize(requirements:, latest_version:)
            @requirements = requirements
            return unless latest_version
            @latest_version = version_class.new(latest_version)
          end

          def updated_requirements
            return requirements unless latest_version

            requirements.map do |req|
              next req unless req[:requirement].match?(/\d/)
              next req if req[:requirement].include?(",")

              # Since range requirements are excluded by the line above we can
              # just do a `gsub` on anything that looks like a version
              new_req =
                req[:requirement].gsub(VERSION_REGEX, latest_version.to_s)
              req.merge(requirement: new_req)
            end
          end

          private

          attr_reader :requirements, :latest_version

          def version_class
            Maven::Version
          end
        end
      end
    end
  end
end
