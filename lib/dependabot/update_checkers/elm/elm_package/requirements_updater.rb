# frozen_string_literal: true

require "dependabot/utils/elm/version"
require "dependabot/utils/elm/requirement"
require "dependabot/update_checkers/elm/elm_package"

module Dependabot
  module UpdateCheckers
    module Elm
      class ElmPackage
        class RequirementsUpdater
          # DEPENDENCY_REGEX = ->(name) /"#{name}": ("[^\"]+")/

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
                {
                  requirement: require_exactly(@latest_resolvable_version),
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

          def require_exactly(version)
            # Elm recommends folks to use exact versions
            # and Elm 0.19 won't support other requirement
            # specifications, so lets force everyone towards it
            "#{version} <= v <= #{version}"
          end
        end
      end
    end
  end
end
