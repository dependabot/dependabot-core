# frozen_string_literal: true

require "dependabot/update_checkers/java_script/base"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class Base
        class RequirementsUpdater
          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/

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

            requirements.map do |req|
              if existing_version
                updated_library_requirement(req)
              else
                updated_app_requirement(req)
              end
            end
          end

          private

          def updated_library_requirement(req)
            updated_requirement =
              req[:requirement].
              sub(VERSION_REGEX) do |old_version|
                old_parts = old_version.split(".")
                new_parts = latest_resolvable_version.to_s.split(".").
                            first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i].match?(/^x\b/) ? "x" : part
                end.join(".")
              end

            req.merge(requirement: updated_requirement)
          end

          def updated_app_requirement(req)
            updated_requirement =
              req[:requirement].
              sub(VERSION_REGEX) do |old_version|
                old_parts = old_version.split(".")
                new_parts = latest_resolvable_version.to_s.split(".").
                            first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i].match?(/^x\b/) ? "x" : part
                end.join(".")
              end

            req.merge(requirement: updated_requirement)
          end
        end
      end
    end
  end
end
