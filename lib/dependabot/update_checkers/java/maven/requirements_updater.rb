# frozen_string_literal: true

#######################################################
# For more details on Maven version constraints, see: #
# https://maven.apache.org/pom.html#Dependencies      #
#######################################################

require "dependabot/update_checkers/java/maven"
require "dependabot/utils/java/version"
require "dependabot/utils/java/requirement"

module Dependabot
  module UpdateCheckers
    module Java
      class Maven
        class RequirementsUpdater
          def initialize(requirements:, latest_version:, source_url:,
                         properties_to_update:)
            @requirements = requirements
            @source_url = source_url
            @properties_to_update = properties_to_update
            return unless latest_version

            @latest_version = version_class.new(latest_version)
          end

          def updated_requirements
            return requirements unless latest_version

            # Note: Order is important here. The FileUpdater needs the updated
            # requirement at index `i` to correspond to the previous requirement
            # at the same index.
            requirements.map do |req|
              next req if req.fetch(:requirement).nil?
              next req if req.fetch(:requirement).include?(",")

              property_name = req.dig(:metadata, :property_name)
              if property_name && !properties_to_update.include?(property_name)
                next req
              end

              new_req = update_requirement(req[:requirement])
              req.merge(requirement: new_req, source: updated_source)
            end
          end

          private

          attr_reader :requirements, :latest_version, :source_url,
                      :properties_to_update

          def update_requirement(req_string)
            if req_string.include?(".+")
              update_dynamic_requirement(req_string)
            else
              # Since range requirements are excluded this must be exact
              update_exact_requirement(req_string)
            end
          end

          def update_exact_requirement(req_string)
            old_version = requirement_class.new(req_string).
                          requirements.first.last
            req_string.gsub(old_version.to_s, latest_version.to_s)
          end

          # This is really only a Gradle thing, but Gradle relies on this
          # RequirementsUpdater too
          def update_dynamic_requirement(req_string)
            precision = req_string.split(".").take_while { |s| s != "+" }.count

            version_parts = latest_version.segments.first(precision)

            version_parts.join(".") + ".+"
          end

          def version_class
            Utils::Java::Version
          end

          def requirement_class
            Utils::Java::Requirement
          end

          def updated_source
            { type: "maven_repo", url: source_url }
          end
        end
      end
    end
  end
end
