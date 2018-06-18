# frozen_string_literal: true

#######################################################################
# For more details on Dotnet version constraints, see:                #
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning #
#######################################################################

require "dependabot/update_checkers/dotnet/nuget"
require "dependabot/utils/dotnet/version"

module Dependabot
  module UpdateCheckers
    module Dotnet
      class Nuget
        class RequirementsUpdater
          VERSION_REGEX = /[0-9a-zA-Z]+(?:\.[a-zA-Z0-9\-]+)*/

          def initialize(requirements:, latest_version:, source_details:)
            @requirements = requirements
            @source_details = source_details
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

              # Since range requirements are excluded by the line above we can
              # just do a `gsub` on anything that looks like a version
              new_req =
                req[:requirement].gsub(VERSION_REGEX, latest_version.to_s)
              req.merge(requirement: new_req, source: updated_source)
            end
          end

          private

          attr_reader :requirements, :latest_version, :source_details

          def version_class
            Utils::Dotnet::Version
          end

          def updated_source
            {
              type: "nuget_repo",
              url: source_details.fetch(:repo_url),
              nuspec_url: source_details.fetch(:nuspec_url)
            }
          end
        end
      end
    end
  end
end
